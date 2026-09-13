# Watch boot hooks during a deploy, from any PowerShell window (edition of
# watch-hooks.sh).
#
# Hooks write their progress to /dev/console as "[<hook_name>] message", so
# boot diagnostics captures it. Every 30s this prints each VM's newest hook
# line from its boot-diagnostics serial log. Run alongside terraform apply;
# Ctrl-C to stop watching.
#
# Prerequisites: az logged in (az login). Run from the deployment repo root
# (.\tools\hooks\watch-hooks.ps1) or from anywhere: when the working directory
# holds no Terraform workspace, the script changes to its own parent directory.
#
# Usage: watch-hooks.ps1 [-ResourceGroup <name>] [-Tags '<hook_name>|<hook_name>|...']
#   ResourceGroup  defaults to the resource_group_unique_name output
#   Tags           defaults to every "[...]" line, including the boot
#                  script's own [main] and [install_package] lines
param(
  [string]$ResourceGroup = '',
  [string]$Tags = '[a-z0-9_-]+'
)
$ErrorActionPreference = 'Continue'

if (-not (Test-Path .terraform) -and -not (Test-Path terraform.tfstate)) {
  Set-Location (Join-Path $PSScriptRoot '..\..')
}
if (-not $ResourceGroup) {
  $ResourceGroup = "$(& terraform output -raw resource_group_unique_name 2>$null)".Trim()
}
if (-not $ResourceGroup) {
  Write-Error 'No resource group recorded in Terraform outputs (mid-first-apply). Pass it: watch-hooks.ps1 -ResourceGroup <your resource_group_name value>'
  exit 1
}

$pattern = "\[($Tags)\][^\p{Cc}\\]{0,300}"
Write-Output "Watching boot-diagnostics logs in $ResourceGroup every 30s for [$Tags] lines (Ctrl-C to stop)"
while ($true) {
  $stamp = Get-Date -Format 'HH:mm:ss'
  $vms = @(& az vm list -g $ResourceGroup --query '[].name' -o tsv 2>$null | Where-Object { $_ })
  if ($vms.Count -eq 0) {
    Write-Output "$stamp no VMs in $ResourceGroup yet"
  } else {
    foreach ($vm in $vms) {
      $log = (& az vm boot-diagnostics get-boot-log -g $ResourceGroup -n $vm 2>$null) -join "`n"
      $matches = [regex]::Matches($log, $pattern)
      if ($matches.Count -gt 0) { $line = $matches[$matches.Count - 1].Value }
      else { $line = 'no hook lines (not reached, done long ago, or log rolled)' }
      Write-Output "$stamp ${vm}: $line"
    }
  }
  Start-Sleep -Seconds 30
}
