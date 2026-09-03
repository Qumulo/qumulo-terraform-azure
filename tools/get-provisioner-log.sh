#!/usr/bin/env bash
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
# Prerequisites: az logged in (az login). Run from the deployment repo root
# (./tools/get-provisioner-log.sh) or from anywhere: when the working
# directory holds no Terraform workspace, the script changes to its own
# parent directory. Uses the az "log-analytics" extension (az installs it on
# first use if missing).

set -euo pipefail

if [ ! -d .terraform ] && [ ! -e terraform.tfstate ]; then
  cd "$(dirname "$0")/.."
fi

RG=$(terraform output -raw resource_group_unique_name 2>/dev/null || true)
if [ -z "$RG" ]; then
  # No outputs recorded (e.g. apply failed very early): derive the resource
  # group from the random suffix resource, which is created first.
  RG=$(terraform show -json | jq -r '.values.root_module.resources[]?
        | select(.address == "random_string.resource_group_suffix")
        | "\(.values.keepers.resource_group_name)-\(.values.result)-rg"')
fi
if [ -z "$RG" ]; then
  echo "ERROR: no deployment found in Terraform state (was anything applied from this directory?)" >&2
  exit 1
fi

WSINFO=$(az monitor log-analytics workspace list -g "$RG" \
  --query "[?ends_with(name, '-logs')] | [0].{name: name, customerId: customerId}" -o json)
WSNAME=$(jq -r '.name // empty' <<<"$WSINFO")
WS=$(jq -r '.customerId // empty' <<<"$WSINFO")
if [ -z "$WS" ]; then
  echo "ERROR: no provisioner log workspace (*-logs) found in resource group $RG." >&2
  echo "The deployment may have failed before log collection was set up, or the workspace was removed." >&2
  exit 1
fi

DUN=${WSNAME%-logs}
OUT="provisioner-log-$DUN.txt"

# cut: the log-analytics extension appends a TableName column to every row.
az monitor log-analytics query -w "$WS" \
  --analytics-query "QumuloProvisioner_CL | sort by TimeGenerated asc | project RawData" \
  -o tsv | cut -f1 > "$OUT"

echo "Wrote $(wc -l < "$OUT") log lines to $OUT"
