#!/usr/bin/env bash
# Streamed into `terraform apply` by terraform_data.hook_watch (hooks-watch.tf),
# which runs it concurrently with the cluster create. Prints each VM's newest
# hook log line whenever it changes, so a boot script blocked in a pre_run or
# post_run hook is visible in the apply output itself. tools/hooks/watch-hooks.sh
# is the standalone equivalent for any other terminal.
#
# Hooks log to the serial console as "[<hook_name>] message", where hook_name is
# the hook's file name with dashes as underscores (hooks/readme.md, "Hook
# contract"). WATCH_TAGS is the |-separated list of the wired hooks' names.
#
# Environment: WATCH_RG, WATCH_TAGS, WATCH_NODE_COUNT, WATCH_EXISTING_VMS
# (required); WATCH_POLL_SECONDS (default 30), WATCH_QUIET_SECONDS (default
# 180), WATCH_MAX_SECONDS (default 7200).
#
# Always exits 0 -- a watcher failure must never fail a deploy. Terraform cannot
# report a failed cluster create until this local-exec ends, so the watch ends
# as soon as the deployment stops moving:
#   - at once when WATCH_EXISTING_VMS >= WATCH_NODE_COUNT: every node already
#     exists, this apply boots no VM (a no-op apply, a settings change);
#   - at once when resources disappear from the group while no VM exists, or
#     when VMs that had appeared are gone: the provider is rolling back a
#     failed create;
#   - at once when a VM disappears while nodes remain: the provider removed
#     its provisioner VM, which it does only after the operation succeeded;
#   - when nothing changed for WATCH_QUIET_SECONDS -- no resource added to or
#     removed from the group, no VM power-state change, no new hook line
#     (hooks must log at least once a minute while they wait); after the last
#     hook releases, this ends the watch while the cluster forms;
#   - at WATCH_MAX_SECONDS, the provider's own timeout window: on a timed-out
#     create a hook waits forever, still refreshing its console line.

set -u

RG="${WATCH_RG:?}"
TAGS="${WATCH_TAGS:?}"
NODE_COUNT="${WATCH_NODE_COUNT:?}"
EXISTING="${WATCH_EXISTING_VMS:?}"
POLL="${WATCH_POLL_SECONDS:-30}"
QUIET="${WATCH_QUIET_SECONDS:-180}"
MAX="${WATCH_MAX_SECONDS:-7200}"

if ! command -v az >/dev/null 2>&1; then
  echo "[hook-watch] az CLI not found on this machine; apply-side hook watch disabled (tools/hooks/watch-hooks.sh still works from a machine with az)"
  exit 0
fi
if [ "${EXISTING:-0}" -ge "$NODE_COUNT" ] 2>/dev/null; then
  echo "[hook-watch] all $NODE_COUNT nodes already exist in $RG; this apply boots no VM, nothing to watch"
  exit 0
fi

STATE=$(mktemp -d)
trap 'rm -rf "$STATE"' EXIT

started=$(date +%s)
last_activity=$started
last_fingerprint=""
peak_resources=0
peak_vms=0
echo "[hook-watch] watching boot logs in $RG for hook lines: $TAGS"

while :; do
  # Resource names only: while the provider is building, the set grows every
  # minute or so, and a rollback shrinks it. Provisioning states are left out --
  # once the cluster runs, its floating-IP reconciler keeps updating NICs, which
  # would look like activity forever.
  resources=$(az resource list -g "$RG" --query "[].name" -o tsv 2>/dev/null | sort || true)
  resource_count=$(printf '%s' "$resources" | grep -c . || true)
  vms=$(az vm list -g "$RG" -d --query "[].[name, powerState]" -o tsv 2>/dev/null | sort || true)
  vm_count=$(printf '%s' "$vms" | grep -c . || true)

  hook_lines=""
  for vm in $(printf '%s\n' "$vms" | awk '{print $1}'); do
    # -o with a bounded, control-character-terminated pattern: early boot logs
    # are one giant ANSI blob with no newlines, and a line-based grep would
    # return the whole blob.
    line=$(az vm boot-diagnostics get-boot-log -g "$RG" -n "$vm" 2>/dev/null \
      | grep -aoE "\[(${TAGS})\][^[:cntrl:]\\\\]{0,300}" | tail -1 || true)
    [ -z "$line" ] && continue
    hook_lines="$hook_lines$vm=$line"$'\n'
    if [ "$line" != "$(cat "$STATE/$vm" 2>/dev/null)" ]; then
      printf '%s' "$line" > "$STATE/$vm"
      echo "[hook-watch] $vm: $line"
    fi
  done

  fingerprint=$(printf '%s\n%s\n%s' "$resources" "$vms" "$hook_lines" | md5sum)
  if [ "$fingerprint" != "$last_fingerprint" ]; then
    last_fingerprint=$fingerprint
    last_activity=$(date +%s)
  fi

  if [ "$vm_count" -eq 0 ] && [ "$resource_count" -lt "$peak_resources" ]; then
    echo "[hook-watch] resources are being removed from $RG before any VM booted: the create is rolling back; standing down"
    exit 0
  fi
  if [ "$vm_count" -eq 0 ] && [ "$peak_vms" -gt 0 ]; then
    echo "[hook-watch] the deployment's VMs are gone: the create is rolling back; standing down"
    exit 0
  fi
  if [ "$vm_count" -gt 0 ] && [ "$vm_count" -lt "$peak_vms" ]; then
    echo "[hook-watch] a VM was removed while the nodes remain: the provisioner finished; standing down"
    exit 0
  fi
  [ "$resource_count" -gt "$peak_resources" ] && peak_resources=$resource_count
  [ "$vm_count" -gt "$peak_vms" ] && peak_vms=$vm_count

  if [ $(($(date +%s) - last_activity)) -ge "$QUIET" ]; then
    echo "[hook-watch] nothing changed in $RG for ${QUIET}s; standing down"
    exit 0
  fi
  if [ $(($(date +%s) - started)) -ge "$MAX" ]; then
    echo "[hook-watch] provider timeout window (${MAX}s) reached; standing down -- VMs still waiting keep logging to their boot-diagnostics serial logs (tools/hooks/watch-hooks.sh)"
    exit 0
  fi
  sleep "$POLL"
done
