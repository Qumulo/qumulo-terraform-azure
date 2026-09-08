# Block boot until the platform's own provisioning drops a marker file.
#
# For environments where separate automation (configuration management, security
# agents, registration tooling) finishes preparing each VM after it boots, and
# the deployment must not proceed until that work is done: this hook waits until
# the marker file named below exists on the VM's local disk. The platform
# automation creates it as its final step.
#
# Wire it as a node and/or provisioner pre_run hook. It has no timeout of its
# own: the provider timeout of the running operation is the backstop.
#
# Inlined verbatim into a bash -xe -o pipefail boot script: no shebang, no
# exit, and nothing may fail outside a condition context.

# =============================================================================
# MARKER FILE
#
# This hook waits for the file below to exist. Your platform automation must
# create it on every VM once the VM is ready; an empty file is enough:
#
#     touch /tmp/provisioning-complete
#
# To wait for a different path, change the default here, or assign
# provisioning_complete_file in an earlier hook of the same chain.
# =============================================================================
wait_for_provisioning_complete_marker="${provisioning_complete_file:-/tmp/provisioning-complete}"

wait_for_provisioning_complete() {
  # Boot diagnostics always captures /dev/console; whether plain stdout
  # reaches the serial log depends on the image's journal config. Write the
  # wait lines to both so `az vm boot-diagnostics get-boot-log` shows the
  # wait while the deploy runs.
  wait_for_provisioning_complete_log() {
    echo "$@"
    echo "$@" > /dev/console 2>/dev/null || true
  }

  local marker="$wait_for_provisioning_complete_marker"
  local attempt=0
  while [ ! -e "$marker" ]; do
    attempt=$((attempt + 1))
    wait_for_provisioning_complete_log "[wait_for_provisioning_complete] waiting for platform automation to create $marker (attempt $attempt)"
    sleep 10
  done
  wait_for_provisioning_complete_log "[wait_for_provisioning_complete] $marker present; continuing boot"
}
wait_for_provisioning_complete
