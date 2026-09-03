#Post-deployment private networking, all in ONE apply. The qumulo provider
#deploys the cluster with public network access enabled and (when
#create_private_endpoints is set) creates the private endpoints -- one per
#storage account, one for the Key Vault, one for the App Configuration store --
#as its final step, with no DNS attached, and reports them in three outputs.
#In the same apply, after the cluster completes, the wrapper:
#  1. Writes A records for the endpoints into the caller's Azure Private DNS
#     zones (or the caller feeds the private_endpoints output to an external
#     DNS system such as Infoblox and skips the zone variables).
#  2. Links the zones to the cluster VNet (manage_dns_zone_vnet_links)
#     strictly AFTER their records exist -- linking an empty privatelink zone
#     would make the endpoint FQDNs resolve NXDOMAIN inside the VNet.
#  3. With disable_public_network_access_post_deploy set, disables public
#     network access on the storage accounts, Key Vault, and App Configuration
#     store -- the true last step. Only offered when the
#     wrapper manages Azure Private DNS (enforced by variable validation): on
#     the external-DNS path the caller owns lockdown, from their own tooling,
#     using the private_endpoints output.
#
#Steps 1-2 live in modules/private-dns and step 3 in modules/network-lockdown,
#mirroring the AWS wrapper's post-cluster modules (route53-resolver, nlb):
#this file computes their inputs from the cluster outputs and orders the
#module calls. Everything is count-based, not for_each: the endpoint details
#are computed during the cluster apply, and Terraform requires for_each keys
#-- but not count values' contents -- to be known at plan time. The counts
#come from inputs: the storage-account count formula and endpoint-name
#suffixes are part of the provider contract (see the engineering spec), and
#per-record preconditions fail loudly if the provider's output ever diverges.

locals {
  #INTERIM: sourced from var.private_endpoints_override until the provider
  #release that ships the outputs. Flip these three to:
  #  qumulo_filesystem_azure.cluster.appconfig_private_endpoint
  #  qumulo_filesystem_azure.cluster.keyvault_private_endpoint
  #  qumulo_filesystem_azure.cluster.storage_private_endpoints
  #and bump the qumulo provider pin in versions.tf when it ships. The
  #bridge-aware count branches below collapse to the formula at the same time.
  appconfig_pe = var.create_private_endpoints ? qumulo_filesystem_azure.cluster.appconfig_private_endpoint : null
  keyvault_pe  = var.create_private_endpoints ? qumulo_filesystem_azure.cluster.keyvault_private_endpoint : null
  storage_pes  = var.create_private_endpoints ? qumulo_filesystem_azure.cluster.storage_private_endpoints : {}

  #Bridge in use = counts come from the supplied override; otherwise from the
  #contract: one storage account (and endpoint) per 200TB of soft capacity,
  #minimum 5, capped at 100; a Key Vault endpoint unless the vault is
  #customer-managed; an App Configuration endpoint always.
  bridge_in_use = var.private_endpoints_override.appconfig != null || var.private_endpoints_override.keyvault != null || length(var.private_endpoints_override.storage) > 0

  storage_pe_count = !var.create_private_endpoints ? 0 : (
    local.bridge_in_use
    ? length(local.storage_pes)
    : min(max(ceil(var.soft_capacity_limit_tb / 200), 5), 100)
  )
  keyvault_pe_count = !var.create_private_endpoints ? 0 : (
    local.bridge_in_use
    ? (local.keyvault_pe != null ? 1 : 0)
    : (var.key_vault_id == null ? 1 : 0)
  )
  appconfig_pe_count = !var.create_private_endpoints ? 0 : (
    local.bridge_in_use ? (local.appconfig_pe != null ? 1 : 0) : 1
  )

  #Storage endpoint lookups, matched by the contractual name suffix
  #"-storage-endpoint-<N>" (1-based). Values are unknown at plan on a fresh
  #deploy; resolved during apply. Regex-anchored so "-storage-endpoint-1"
  #never matches "-storage-endpoint-11".
  storage_pe_matches = [
    for i in range(local.storage_pe_count) : [
      for pe in values(local.storage_pes) : pe
      if can(regex(format("-storage-endpoint-%d$", i + 1), pe.endpoint_name))
    ]
  ]

  #The cluster VNet, for the zone links.
  vnet_id = "/subscriptions/${local.subnet_id_parts.subscription_id}/resourceGroups/${local.subnet_id_parts.resource_group}/providers/Microsoft.Network/virtualNetworks/${local.subnet_id_parts.vnet_name}"

  #Azure-DNS mode: any zone supplied. Unset zones = external-DNS mode; the
  #caller feeds the private_endpoints output to their own DNS system.
  manage_azure_dns = var.blob_private_dns_zone_id != null || var.keyvault_private_dns_zone_id != null || var.appconfig_private_dns_zone_id != null

  #Subscription for the azurerm.dns provider alias, parsed from the zone
  #resource IDs (all supplied zones are validated to share one). A zone
  #resource ID is /subscriptions/<sub>/resourceGroups/<rg>/providers/
  #Microsoft.Network/privateDnsZones/<zone>.
  dns_zone_subscription_id = try(coalesce(
    var.blob_private_dns_zone_id == null ? null : split("/", var.blob_private_dns_zone_id)[2],
    var.keyvault_private_dns_zone_id == null ? null : split("/", var.keyvault_private_dns_zone_id)[2],
    var.appconfig_private_dns_zone_id == null ? null : split("/", var.appconfig_private_dns_zone_id)[2],
  ), null)
}

#Stage 2: A records into the caller's Azure Private DNS zones, then
#zone-to-VNet links strictly after the records exist. The module's default
#azurerm provider is the DNS-subscription alias, so its resources carry no
#alias plumbing.
module "private_dns" {
  source = "./modules/private-dns"
  count  = local.manage_azure_dns ? 1 : 0

  providers = {
    azurerm = azurerm.dns
  }

  blob_private_dns_zone_id      = var.blob_private_dns_zone_id
  keyvault_private_dns_zone_id  = var.keyvault_private_dns_zone_id
  appconfig_private_dns_zone_id = var.appconfig_private_dns_zone_id

  manage_vnet_links = var.manage_dns_zone_vnet_links
  vnet_id           = local.vnet_id
  vnet_link_name    = local.subnet_id_parts.vnet_name
  tags              = var.tags

  storage_endpoint_candidates = local.storage_pe_matches
  storage_count               = local.storage_pe_count
  keyvault_endpoint           = local.keyvault_pe
  keyvault_count              = local.keyvault_pe_count
  appconfig_endpoint          = local.appconfig_pe
  appconfig_count             = local.appconfig_pe_count
}

#Stage 3: disable public network access, strictly after the records and zone
#links exist -- the module boundary is the seam where the qumulo provider's
#planned network-lockdown resource will land (see modules/network-lockdown).
#Targets are ordered storage 1..N, then Key Vault, then App Configuration;
#lockdown_target_count mirrors that order with plan-time-known arithmetic
#because count must be known at plan while the IDs are computed during apply.
locals {
  lockdown_targets = concat(
    [for i in range(local.storage_pe_count) : {
      resource_id = one(local.storage_pe_matches[i]).target_resource_id
      type        = "Microsoft.Storage/storageAccounts@2024-01-01"
    }],
    var.key_vault_id == null && local.keyvault_pe_count > 0 ? [{
      resource_id = local.keyvault_pe.target_resource_id
      type        = "Microsoft.KeyVault/vaults@2023-07-01"
    }] : [],
    local.appconfig_pe_count > 0 ? [{
      resource_id = local.appconfig_pe.target_resource_id
      type        = "Microsoft.AppConfiguration/configurationStores@2024-05-01"
    }] : [],
  )
  lockdown_target_count = local.storage_pe_count + (var.key_vault_id == null ? local.keyvault_pe_count : 0) + local.appconfig_pe_count
}

module "network_lockdown" {
  source = "./modules/network-lockdown"
  count  = var.disable_public_network_access_post_deploy ? 1 : 0

  targets      = local.lockdown_targets
  target_count = local.lockdown_target_count

  depends_on = [module.private_dns]
}
