#!/usr/bin/env bash
# Watch boot hooks during a deploy, from any terminal.
#
# Hooks write their progress to /dev/console as "[<hook_name>] message", so
# boot diagnostics captures it. Every 30s this prints each VM's newest hook
# line from its boot-diagnostics serial log. Run alongside terraform apply;
# Ctrl-C to stop watching.
#
# Prerequisites: az logged in (az login). Run from the deployment repo root
# (./tools/hooks/watch-hooks.sh) or from anywhere: when the working directory
# holds no Terraform workspace, the script changes to its own parent directory.
#
# Usage: watch-hooks.sh [<resource-group>] [<hook_name>|<hook_name>|...]
#   resource-group  defaults to the resource_group_unique_name output
#   hook names      defaults to every "[...]" line, including the boot
#                   script's own [main] and [install_package] lines

set -euo pipefail

if [ ! -d .terraform ] && [ ! -e terraform.tfstate ]; then
  cd "$(dirname "$0")/../.."
fi

RG=${1:-$(terraform output -raw resource_group_unique_name 2>/dev/null || true)}
TAGS=${2:-[a-z0-9_-]+}
if [ -z "$RG" ]; then
  echo "ERROR: no resource group recorded in Terraform outputs (mid-first-apply)." >&2
  echo "Pass the resource group name (your resource_group_name value): $0 <resource-group>" >&2
  exit 1
fi

echo "Watching boot-diagnostics logs in $RG every 30s for [$TAGS] lines (Ctrl-C to stop)"
while :; do
  VMS=$(az vm list -g "$RG" --query '[].name' -o tsv 2>/dev/null || true)
  if [ -z "$VMS" ]; then
    echo "$(date +%T) no VMs in $RG yet"
  else
    for VM in $VMS; do
      # -o with a bounded, control-character-terminated pattern: early boot
      # logs are one giant ANSI blob with no newlines, and a line-based grep
      # would return the whole blob.
      LINE=$(az vm boot-diagnostics get-boot-log -g "$RG" -n "$VM" 2>/dev/null \
        | grep -aoE "\[(${TAGS})\][^[:cntrl:]\\\\]{0,300}" | tail -1 || true)
      echo "$(date +%T) $VM: ${LINE:-no hook lines (not reached, done long ago, or log rolled)}"
    done
  fi
  sleep 30
done
