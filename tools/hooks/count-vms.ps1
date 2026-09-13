# External data program for hooks-watch.tf, PowerShell edition of count-vms.sh: how
# many VMs the deployment resource group holds at plan time. Reads
# {"resource_group": "..."} on stdin, prints {"count": "N"}. A missing group, a
# missing az CLI, or a logged-out az all count as 0 -- the watch then runs and
# reports the az problem itself.
$ErrorActionPreference = 'Continue'
$rg = $null
try { $rg = ([Console]::In.ReadToEnd() | ConvertFrom-Json).resource_group } catch { }
$count = 0
if ($rg -and (Get-Command az -ErrorAction SilentlyContinue)) {
  $out = "$(& az vm list -g $rg --query 'length(@)' -o tsv 2>$null)".Trim()
  if ($LASTEXITCODE -eq 0 -and $out -match '^\d+$') { $count = [int]$out }
}
Write-Output ('{"count": "' + $count + '"}')
