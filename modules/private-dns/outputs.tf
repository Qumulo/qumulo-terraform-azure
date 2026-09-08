output "records" {
  description = "fqdn => private IP for every A record this module wrote."
  value = merge(
    { for i, r in azurerm_private_dns_a_record.blob : one(var.storage_endpoint_candidates[i]).fqdn => tolist(r.records)[0] },
    { for i, r in azurerm_private_dns_a_record.keyvault : var.keyvault_endpoint.fqdn => tolist(r.records)[0] },
    { for i, r in azurerm_private_dns_a_record.appconfig : var.appconfig_endpoint.fqdn => tolist(r.records)[0] },
  )
}
