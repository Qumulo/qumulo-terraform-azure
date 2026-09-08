# Block boot until Red Hat subscription content is installable.
#
# For BYOS / Red Hat gold images (Azure Cloud Access, private image catalogs),
# dnf has zero usable repos until the VM is registered with RHSM or Satellite.
# When registration is done by an external async process, first boot races it
# and every package install fails. This hook waits until dnf can actually
# resolve a package, and only then lets the boot script continue. No timeout:
# the provider timeout of the running operation is the backstop.
#
# Wire it as a pre_run hook (it runs before the boot script's first install):
#   node_hooks_files        = { pre_run_file = "wait-for-rhel-entitlement.sh", ... }
#   provisioner_hooks_files = { pre_run_file = "wait-for-rhel-entitlement.sh", ... }
#
# Inlined verbatim into a bash -xe -o pipefail boot script: no shebang, no
# exit, and nothing may fail outside a condition context.

wait_for_rhel_entitlement() {
  # Boot diagnostics always captures /dev/console; whether plain stdout
  # reaches the serial log depends on the image's journal config. Write the
  # wait lines to both so `az vm boot-diagnostics get-boot-log` shows the
  # wait while the deploy runs (tools/hooks/watch-hooks.sh tails it).
  wait_for_rhel_entitlement_log() {
    echo "$@"
    echo "$@" > /dev/console 2>/dev/null || true
  }

  if ! command -v dnf >/dev/null 2>&1; then
    wait_for_rhel_entitlement_log "[wait_for_rhel_entitlement] no dnf on this image; nothing to wait for"
    return 0
  fi

  local start elapsed
  start=$(date +%s)

  # Two conditions, core dnf only (no dnf-plugins-core on a stripped image):
  # a RHEL repo is enabled (registration wrote redhat.repo; dnf exits 0 even
  # with zero repos, so test repolist's OUTPUT, not its exit code), and
  # makecache succeeds (the repo metadata is actually fetchable). PAYG/RHUI,
  # already-registered, and non-RHSM images pass on the first try.
  while ! { dnf -q repolist 2>/dev/null | grep -qi rhel && dnf -q -y makecache >/dev/null 2>&1; }; do
    elapsed=$(($(date +%s) - start))
    wait_for_rhel_entitlement_log "[wait_for_rhel_entitlement] no installable RHEL content after ${elapsed}s; waiting for subscription registration"
    dnf -q repolist 2>/dev/null || true
    if command -v subscription-manager >/dev/null 2>&1; then
      subscription-manager identity 2>&1 | head -2 || true
      subscription-manager status 2>&1 | grep -iE 'overall|content access' || true
    fi
    sleep 30
  done

  elapsed=$(($(date +%s) - start))
  wait_for_rhel_entitlement_log "[wait_for_rhel_entitlement] installable content available after ${elapsed}s"
  dnf -q repolist 2>/dev/null || true
}
wait_for_rhel_entitlement
