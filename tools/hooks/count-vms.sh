#!/usr/bin/env bash
# External data program for hooks-watch.tf: how many VMs the deployment resource
# group holds at plan time. Reads {"resource_group": "..."} on stdin, prints
# {"count": "N"}. A missing group, a missing az CLI, or a logged-out az all
# count as 0 -- the watch then runs and reports the az problem itself.
set -u
rg=$(sed -n 's/.*"resource_group": *"\([^"]*\)".*/\1/p')
count=0
if command -v az >/dev/null 2>&1 && [ -n "$rg" ]; then
  count=$(az vm list -g "$rg" --query 'length(@)' -o tsv 2>/dev/null || echo 0)
fi
printf '{"count": "%s"}\n' "${count:-0}"
