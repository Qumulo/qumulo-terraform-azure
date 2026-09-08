# Block boot until the platform's own provisioning drops a marker file.
#
# For environments where separate automation (configuration management, security
# agents, registration tooling) finishes preparing each VM after it boots, and
# the deployment must not proceed until that work is done: this hook waits until
# a marker file exists on the VM's local disk. The platform automation creates
# the marker as its final step. Default path /tmp/provisioning-complete;
# assign provisioning_complete_file before this hook runs (for example in an
# earlier pre_run file in the chain) to override it.
#
# Wire it as a node and/or provisioner pre_run hook. It has no timeout of its
# own: the provider timeout of the running operation is the backstop.
#
# Inlined verbatim into a bash -xe -o pipefail boot script: no shebang, no
# exit, and nothing may fail outside a condition context.

wait_for_provisioning_complete() {
  # Boot diagnostics always captures /dev/console; whether plain stdout
  # reaches the serial log depends on the image's journal config. Write the
  # wait lines to both so `az vm boot-diagnostics get-boot-log` shows the
  # wait while the deploy runs.
  wait_for_provisioning_complete_log() {
    echo "$@"
    echo "$@" > /dev/console 2>/dev/null || true
  }

  local marker="${provisioning_complete_file:-/tmp/provisioning-complete}"
  local attempt=0
  while [ ! -e "$marker" ]; do
    attempt=$((attempt + 1))
    wait_for_provisioning_complete_log "[wait_for_provisioning_complete] waiting for $marker (attempt $attempt)"
    sleep 10
  done
  wait_for_provisioning_complete_log "[wait_for_provisioning_complete] $marker present; continuing boot"
}
wait_for_provisioning_complete
