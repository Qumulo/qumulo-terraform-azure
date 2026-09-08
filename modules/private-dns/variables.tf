variable "blob_private_dns_zone_id" {
  description = "Full resource ID of the privatelink blob zone; null skips the storage records."
  type        = string
  nullable    = true
}

variable "keyvault_private_dns_zone_id" {
  description = "Full resource ID of the privatelink vaultcore zone; null skips the Key Vault record."
  type        = string
  nullable    = true
}

variable "appconfig_private_dns_zone_id" {
  description = "Full resource ID of the privatelink azconfig zone; null skips the App Configuration record."
  type        = string
  nullable    = true
}

variable "manage_vnet_links" {
  description = "Link each supplied zone to the cluster VNet, strictly after its records exist. False when the zones are already linked."
  type        = bool
  nullable    = false
}

variable "vnet_id" {
  description = "Full resource ID of the cluster VNet, the link target."
  type        = string
}

variable "vnet_link_name" {
  description = "Name for the zone-to-VNet links (the VNet name; link names are unique per zone)."
  type        = string
}

variable "storage_endpoint_candidates" {
  description = "Per storage index (1-based order), the provider endpoints whose name matched that index -- exactly one entry each when the provider honors the naming contract. Values may be unknown at plan; storage_count carries the plan-time length."
  type = list(list(object({
    fqdn               = string
    ip_address         = string
    endpoint_name      = string
    resource_group     = string
    target_resource_id = string
  })))
}

variable "storage_count" {
  description = "Plan-time-known number of storage endpoints."
  type        = number
  nullable    = false
}

variable "keyvault_endpoint" {
  description = "The Key Vault endpoint details; null when no vault endpoint exists."
  type = object({
    fqdn       = string
    ip_address = string
  })
  nullable = true
}

variable "keyvault_count" {
  description = "Plan-time-known 0 or 1: whether a Key Vault record is expected."
  type        = number
  nullable    = false
}

variable "appconfig_endpoint" {
  description = "The App Configuration endpoint details; null when no endpoint exists."
  type = object({
    fqdn       = string
    ip_address = string
  })
  nullable = true
}

variable "appconfig_count" {
  description = "Plan-time-known 0 or 1: whether an App Configuration record is expected."
  type        = number
  nullable    = false
}

variable "tags" {
  description = "Tags for the VNet links."
  type        = map(string)
  nullable    = true
}
