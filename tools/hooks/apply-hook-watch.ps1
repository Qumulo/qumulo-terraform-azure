# PowerShell edition of apply-hook-watch.sh, run by terraform_data.hook_watch
# (hooks-watch.tf) when hooks_watch_shell is "powershell" or "pwsh". Streams each
# VM's newest hook log line into `terraform apply` whenever it changes, so a boot
# script blocked in a pre_run or post_run hook is visible in the apply output.
# tools/hooks/watch-hooks.ps1 is the standalone equivalent for any other window.
#
# Hooks log to the serial console as "[<hook_name>] message", where hook_name is
# the hook's file name with dashes as underscores (hooks/readme.md, "Hook
# contract"). WATCH_TAGS is the |-separated list of the wired hooks' names.
#
# Environment: WATCH_RG, WATCH_TAGS, WATCH_NODE_COUNT, WATCH_EXISTING_VMS
# (required); WATCH_POLL_SECONDS (default 30), WATCH_QUIET_SECONDS (default
# 180), WATCH_MAX_SECONDS (default 7200).
#
# Always exits 0 -- a watcher failure must never fail a deploy. The stand-down
# rules are the bash script's: every node already exists; a rollback (resources
# or VMs disappearing before the nodes exist); a VM removed while nodes remain
# (the provisioner finished); nothing changed for WATCH_QUIET_SECONDS; or the
# provider's own timeout window WATCH_MAX_SECONDS.
$ErrorActionPreference = 'Continue'

function Get-EnvOr([string]$name, $default) {
  $v = [Environment]::GetEnvironmentVariable($name)
  if ([string]::IsNullOrEmpty($v)) { return $default }
  return $v
}

$RG = Get-EnvOr 'WATCH_RG' ''
$TAGS = Get-EnvOr 'WATCH_TAGS' ''
$NODE_COUNT = [int](Get-EnvOr 'WATCH_NODE_COUNT' 0)
$EXISTING = [int](Get-EnvOr 'WATCH_EXISTING_VMS' 0)
$POLL = [int](Get-EnvOr 'WATCH_POLL_SECONDS' 30)
$QUIET = [int](Get-EnvOr 'WATCH_QUIET_SECONDS' 180)
$MAX = [int](Get-EnvOr 'WATCH_MAX_SECONDS' 7200)

if (-not $RG -or -not $TAGS) {
  Write-Output '[hook-watch] WATCH_RG or WATCH_TAGS not set; nothing to watch'
  exit 0
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Write-Output '[hook-watch] az CLI not found on this machine; apply-side hook watch disabled (tools/hooks/watch-hooks.ps1 still works from a machine with az)'
  exit 0
}
if ($EXISTING -ge $NODE_COUNT) {
  Write-Output "[hook-watch] all $NODE_COUNT nodes already exist in $RG; this apply boots no VM, nothing to watch"
  exit 0
}

# A bounded match that stops at any control character: early boot logs are one
# giant ANSI blob with no newlines, and a line-based match would return the blob.
$pattern = "\[($TAGS)\][^\p{Cc}\\]{0,300}"
$lastLine = @{}
$started = Get-Date
$lastActivity = $started
$lastFingerprint = ''
$peakResources = 0
$peakVms = 0
Write-Output "[hook-watch] watching boot logs in $RG for hook lines: $TAGS"

while ($true) {
  # Resource names only: while the provider is building, the set grows every
  # minute or so, and a rollback shrinks it. Provisioning states are left out --
  # once the cluster runs, its floating-IP reconciler keeps updating NICs, which
  # would look like activity forever.
  $resources = @(& az resource list -g $RG --query '[].name' -o tsv 2>$null | Where-Object { $_ } | Sort-Object)
  $vmRows = @(& az vm list -g $RG -d --query '[].[name, powerState]' -o tsv 2>$null | Where-Object { $_ } | Sort-Object)
  $vmNames = @($vmRows | ForEach-Object { ($_ -split "`t")[0] })

  $hookLines = ''
  foreach ($vm in $vmNames) {
    $log = (& az vm boot-diagnostics get-boot-log -g $RG -n $vm 2>$null) -join "`n"
    if (-not $log) { continue }
    $matches = [regex]::Matches($log, $pattern)
    if ($matches.Count -eq 0) { continue }
    $line = $matches[$matches.Count - 1].Value
    $hookLines += "$vm=$line`n"
    if ($lastLine[$vm] -ne $line) {
      $lastLine[$vm] = $line
      Write-Output "[hook-watch] ${vm}: $line"
    }
  }

  $fingerprint = ($resources -join "`n") + "`n" + ($vmRows -join "`n") + "`n" + $hookLines
  if ($fingerprint -ne $lastFingerprint) {
    $lastFingerprint = $fingerprint
    $lastActivity = Get-Date
  }
  $resourceCount = $resources.Count
  $vmCount = $vmNames.Count

  if ($vmCount -eq 0 -and $resourceCount -lt $peakResources) {
    Write-Output "[hook-watch] resources are being removed from $RG before any VM booted: the create is rolling back; standing down"
    exit 0
  }
  if ($vmCount -eq 0 -and $peakVms -gt 0) {
    Write-Output "[hook-watch] the deployment's VMs are gone: the create is rolling back; standing down"
    exit 0
  }
  if ($vmCount -gt 0 -and $vmCount -lt $peakVms) {
    Write-Output "[hook-watch] a VM was removed while the nodes remain: the provisioner finished; standing down"
    exit 0
  }
  if ($resourceCount -gt $peakResources) { $peakResources = $resourceCount }
  if ($vmCount -gt $peakVms) { $peakVms = $vmCount }

  if (((Get-Date) - $lastActivity).TotalSeconds -ge $QUIET) {
    Write-Output "[hook-watch] nothing changed in $RG for ${QUIET}s; standing down"
    exit 0
  }
  if (((Get-Date) - $started).TotalSeconds -ge $MAX) {
    Write-Output "[hook-watch] provider timeout window (${MAX}s) reached; standing down -- VMs still waiting keep logging to their boot-diagnostics serial logs (tools/hooks/watch-hooks.ps1)"
    exit 0
  }
  Start-Sleep -Seconds $POLL
}
