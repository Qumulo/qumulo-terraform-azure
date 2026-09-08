#Azure Private DNS wiring for the provider-created private endpoints: A records
#into the caller's privatelink zones, then zone-to-VNet links strictly after
#the records exist -- a linked privatelink zone is authoritative inside the
#VNet, so linking an empty one turns the endpoint FQDNs into NXDOMAIN for the
#running cluster. The caller passes the DNS-subscription azurerm provider as
#this module's default azurerm.
#
#Everything is count-based, not for_each: the endpoint details are computed
#during the cluster apply, and Terraform requires for_each keys -- but not
#count values' contents -- to be known at plan time. The counts arrive as
#plan-time-known inputs; per-record preconditions fail loudly if the
#provider's output diverges from the naming contract.
#
#SWAP POINT: if the qumulo provider grows zone-group support that supersedes
#wrapper-written records (open decision with engineering), this module is what
#shrinks or goes away; the root call and its inputs are the interface.

resource "azurerm_private_dns_a_record" "blob" {
  count = var.blob_private_dns_zone_id != null ? var.storage_count : 0

  name                = split(".", one(var.storage_endpoint_candidates[count.index]).fqdn)[0]
  private_dns_zone_id = var.blob_private_dns_zone_id
  ttl                 = 10
  records             = [one(var.storage_endpoint_candidates[count.index]).ip_address]

  lifecycle {
    precondition {
      condition     = length(var.storage_endpoint_candidates[count.index]) == 1
      error_message = "Expected exactly one private endpoint named *-storage-endpoint-${count.index + 1} in the provider's storage endpoints, found ${length(var.storage_endpoint_candidates[count.index])}. The provider's storage-account count formula or endpoint naming no longer matches the wrapper's copy of the contract."
    }
  }
}

resource "azurerm_private_dns_a_record" "keyvault" {
  count = var.keyvault_private_dns_zone_id != null ? var.keyvault_count : 0

  name                = split(".", var.keyvault_endpoint.fqdn)[0]
  private_dns_zone_id = var.keyvault_private_dns_zone_id
  ttl                 = 10
  records             = [var.keyvault_endpoint.ip_address]
}

resource "azurerm_private_dns_a_record" "appconfig" {
  count = var.appconfig_private_dns_zone_id != null ? var.appconfig_count : 0

  name                = split(".", var.appconfig_endpoint.fqdn)[0]
  private_dns_zone_id = var.appconfig_private_dns_zone_id
  ttl                 = 10
  records             = [var.appconfig_endpoint.ip_address]
}

#One link per (zone, VNet) exists in Azure -- when the zones are already
#linked to this VNet (shared hub zones, or a second cluster in the same VNet),
#the caller sets manage_vnet_links = false; the records-before-link ordering
#then cannot be guaranteed for THIS deployment, see the README hazard.
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count = var.blob_private_dns_zone_id != null && var.manage_vnet_links ? 1 : 0

  name                 = var.vnet_link_name
  private_dns_zone_id  = var.blob_private_dns_zone_id
  virtual_network_id   = var.vnet_id
  registration_enabled = false
  tags                 = var.tags

  depends_on = [azurerm_private_dns_a_record.blob]
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  count = var.keyvault_private_dns_zone_id != null && var.manage_vnet_links ? 1 : 0

  name                 = var.vnet_link_name
  private_dns_zone_id  = var.keyvault_private_dns_zone_id
  virtual_network_id   = var.vnet_id
  registration_enabled = false
  tags                 = var.tags

  depends_on = [azurerm_private_dns_a_record.keyvault]
}

resource "azurerm_private_dns_zone_virtual_network_link" "appconfig" {
  count = var.appconfig_private_dns_zone_id != null && var.manage_vnet_links ? 1 : 0

  name                 = var.vnet_link_name
  private_dns_zone_id  = var.appconfig_private_dns_zone_id
  virtual_network_id   = var.vnet_id
  registration_enabled = false
  tags                 = var.tags

  depends_on = [azurerm_private_dns_a_record.appconfig]
}
