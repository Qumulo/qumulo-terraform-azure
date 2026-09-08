# Example: fully private deployment in ONE apply (Azure Private DNS path).
#
# The apply runs, in order: cluster deployment (public access on; the provider creates the
# storage, Key Vault, and App Configuration private endpoints as its final step, no DNS
# attached) -> A records into your privatelink zones -> zone-to-VNet links (only after the
# records exist, so in-VNet resolution never sees an empty privatelink zone) ->
# delay -> public network access disabled on the storage accounts, Key Vault, and App
# Configuration store.
#
# External-DNS variant (e.g. Infoblox): omit the three zone IDs and leave
# disable_public_network_access_post_deploy false (validation enforces this pairing). Feed the
# module's private_endpoints output to your DNS system, and once its records serve, disable
# public access from your own tooling -- each output entry carries the target_resource_id to
# PATCH with publicNetworkAccess = "Disabled".
#
# Pre-linked zones: if a privatelink zone is already linked to this VNet (shared hub zone, or a
# second cluster in the same VNet), set manage_dns_zone_vnet_links = false and read the README
# hazard first -- endpoint names resolve NXDOMAIN inside the VNet mid-deployment.
#
# After lockdown, run applies that add capacity from a network that resolves and reaches the
# private endpoints (scale-ups write SAS definitions to the Key Vault data plane). Destroy
# needs no special access and no re-enabling: it is control-plane only, and the lockdown
# resources are deliberately no-ops on destroy so the wrapper never re-opens public access.

module "cloud_native_qumulo_private" {
  source = "../"
  # ****************************** QUMULO PROVIDER VARIABLES ********************
  #-----------REQUIRED-------------------
  deployment_name     = "cnq-priv-01"
  location            = "eastus2"
  resource_group_name = "rg-qumulo-priv"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
  vm_type             = "Standard_L8s_v4"

  admin_pwd_or_keyvault_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault_name>/secrets/<secret_name>"
  cluster_name                    = "CNQ-PRIV"
  cluster_product_type            = "HOT"
  node_count                      = 3

  #------------PRIVATE NETWORKING------------------
  # Per-resource selection: this example puts storage and Key Vault behind
  # private endpoints and leaves App Configuration on its public endpoint.
  create_storage_private_endpoint   = true
  create_keyvault_private_endpoint  = true
  create_appconfig_private_endpoint = false

  # Azure Private DNS path (omit all three for external DNS such as Infoblox and use the
  # private_endpoints output instead):
  blob_private_dns_zone_id     = "/subscriptions/<sub>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  keyvault_private_dns_zone_id = "/subscriptions/<sub>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"

  # Last step of the same apply (Azure DNS path only; omit on the external-DNS path):
  disable_public_network_access_post_deploy = true
}

# The feed for external DNS: one entry per private endpoint (storage accounts, Key Vault,
# App Configuration) with the FQDN to publish and its private IP.
output "private_endpoints" {
  value = module.cloud_native_qumulo_private.private_endpoints
}
