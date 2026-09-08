# Block provisioning until every private endpoint FQDN resolves privately.
#
# For environments where platform automation locks down public access on new
# storage/Key Vault/App Configuration resources and publishes private-endpoint
# DNS records asynchronously (a scraper, Infoblox automation, etc.), the
# deployment must not touch those services until in-VNet DNS returns the
# endpoints' private IPs. This PROVISIONER pre_run hook derives the deployment's
# endpoint FQDNs and waits, with no timeout: the provider's deployment timeout
# is the backstop.
#
# Wire it as the provisioner pre_run hook only (node hooks run in a separate
# script without the deployment variables, and the provisioner gate is
# sufficient: cluster create does not start until this releases):
#   provisioner_hooks_files = { pre_run_file = "wait-for-private-endpoints.sh", ... }
#
# Relies on variables provision.sh assigns above its pre_run hook point:
# deployment_name, cluster_persistent_capacity_limit, keyvault_uri,
# appconfig_endpoint. Inlined into a bash -xe script: no shebang, no exit,
# probes in condition contexts only.

wait_for_private_endpoints() {
  wait_for_private_endpoints_log() {
    echo "$@"
    echo "$@" > /dev/console 2>/dev/null || true
  }

  # Storage account names are the deployment name with dashes stripped plus a
  # 1-based index; the count mirrors the provider's capacity formula (one
  # account per 200TB, minimum 5, cap 100).
  local base count limit fqdns fqdn ip pending start elapsed i
  base=$(echo "${deployment_name}" | tr -d '-')
  limit=${cluster_persistent_capacity_limit:-100}
  count=$(( (limit + 199) / 200 ))
  [ "$count" -lt 5 ] && count=5
  [ "$count" -gt 100 ] && count=100

  fqdns=""
  for i in $(seq 1 "$count"); do
    fqdns="$fqdns ${base}${i}.blob.core.windows.net"
  done
  if [ -n "${keyvault_uri:-}" ]; then
    fqdns="$fqdns $(echo "$keyvault_uri" | sed -e 's|https://||' -e 's|/.*||')"
  fi
  if [ -n "${appconfig_endpoint:-}" ]; then
    fqdns="$fqdns $(echo "$appconfig_endpoint" | sed -e 's|https://||' -e 's|/.*||')"
  fi

  wait_for_private_endpoints_log "[wait_for_private_endpoints] waiting for private resolution of:$fqdns"
  start=$(date +%s)

  while : ; do
    pending=""
    for fqdn in $fqdns; do
      # A name with a private endpoint is unresolvable (or already private)
      # here: the endpoints exist before the provisioner boots, and endpoint
      # creation immediately points the public name into the privatelink
      # zone. So a name that still resolves cleanly has no private endpoint
      # in play (BYO vault, a service left public) and is already reachable
      # -- count it satisfied. Wait only on names with no answer.
      ip=$(getent hosts "$fqdn" 2>/dev/null | awk '{print $1; exit}')
      if [ -z "$ip" ]; then
        pending="$pending $fqdn(unresolved)"
      fi
    done
    if [ -z "$pending" ]; then
      elapsed=$(($(date +%s) - start))
      wait_for_private_endpoints_log "[wait_for_private_endpoints] all endpoints resolvable after ${elapsed}s"
      break
    fi
    elapsed=$(($(date +%s) - start))
    wait_for_private_endpoints_log "[wait_for_private_endpoints] still public/unresolved after ${elapsed}s:$pending"
    sleep 30
  done
}
wait_for_private_endpoints
