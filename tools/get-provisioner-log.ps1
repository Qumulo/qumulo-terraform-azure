# Export this deployment's provisioner log to a shareable text file.
#
# The provisioner streams its run log (/var/log/cloud-init-output.log) into a
# Log Analytics workspace named "<deployment_unique_name>-logs" in the
# deployment's resource group (30-day retention), custom table
# QumuloProvisioner_CL. This pulls the whole transcript, in order, log lines
# only.
#
# Works on failed/partial deployments too: it never reads the
# deployment_unique_name output (absent when the cluster resource failed) --
# the resource group comes from the resource_group_unique_name output or,
# failing that, straight from the Terraform state, and the deployment name is
# recovered from the workspace itself.
#
# Prerequisites:
#   - Az PowerShell modules:  Install-Module Az.Accounts, Az.OperationalInsights
#   - Signed in:              Connect-AzAccount  (Set-AzContext if you have
#                             multiple subscriptions)
#   - Run from the deployment repo root (.\tools\get-provisioner-log.ps1) or
#     from anywhere: when the working directory holds no Terraform workspace,
#     the script changes to its own parent directory.

param([string]$ResourceGroup)

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".terraform") -and -not (Test-Path "terraform.tfstate")) {
    Set-Location (Join-Path $PSScriptRoot "..")
}

$ctx = Get-AzContext
if (-not $ctx -or -not $ctx.Subscription) {
    throw "No Azure subscription context. Run Connect-AzAccount first (add -UseDeviceAuthentication on a browserless host; Set-AzContext -Subscription <id> if you have several), then re-run this script."
}

# The resource group name is the resource_group_name input, used verbatim.
# The output covers the normal case; a failed first apply may have recorded
# no outputs, so accept the name as a parameter for that case.
$rg = $ResourceGroup
if (-not $rg) { $rg = terraform output -raw resource_group_unique_name 2>$null }
if (-not $rg) {
    throw "No resource group recorded in Terraform outputs (the apply may have failed early). Pass your resource_group_name value: .\tools\get-provisioner-log.ps1 -ResourceGroup <name>"
}

$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $rg |
    Where-Object Name -like "*-logs" | Select-Object -First 1
if (-not $workspace) {
    throw "No provisioner log workspace (*-logs) found in resource group $rg. The deployment may have failed before log collection was set up, or the workspace was removed."
}

$dun = $workspace.Name -replace "-logs$", ""

$result = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId `
    -Query "QumuloProvisioner_CL | sort by TimeGenerated asc | project RawData"

$outFile = "provisioner-log-$dun.txt"
$result.Results | ForEach-Object { $_.RawData } | Out-File -FilePath $outFile -Encoding utf8

Write-Host "Wrote $((Get-Content $outFile).Count) log lines to $outFile"
