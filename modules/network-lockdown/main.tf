#Disables public network access on the deployment's storage accounts, Key
#Vault, and App Configuration store, strictly after the caller's DNS work
#(this module is called with depends_on the records and zone links).
#
#INTERIM INTERNALS -- SWAP POINT. This stands in for the qumulo provider's
#planned network-lockdown resource (requested from engineering); when that
#ships, these internals become a single
#  resource "qumulo_filesystem_azure_network_lockdown" { ... }
#taking var.targets[*].resource_id, and azapi leaves the wrapper. The module
#interface and the root graph do not change.
#
#azapi_resource_action with method PATCH: a true partial update carrying only
#publicNetworkAccess, because a full read-merge-PUT (azapi_update_resource,
#az storage account update) round-trips properties Azure accepts on read but
#rejects on write -- observed with accessTier "Smart" on intelligent-storage
#accounts. Actions perform no API call on destroy, so destroying this module
#never re-opens public access. (The future provider resource will instead
#re-enable public access on delete, which also gives teardown the safe
#ordering: re-open first, then remove DNS, then the cluster.)
#
#No settle delay: the cluster resolves names per-connection with no cache of
#its own, the node OS resolver holds displaced public answers for at most 60s
#(measured TTLs), and a connection racing the cutover fails to the closed
#public path and is retried.
resource "azapi_resource_action" "disable_public_network_access" {
  count = var.target_count

  type        = var.targets[count.index].type
  resource_id = var.targets[count.index].resource_id
  method      = "PATCH"
  body = {
    properties = {
      publicNetworkAccess = "Disabled"
    }
  }
}
