# Example: deploying into Azure Government instead of the Azure Public cloud.
#
# Differences from a standard deployment:
#   - azure_environment must be set to "usgovernment" (both the qumulo provider's azure{} block
#     and, if you configure one directly, any azurerm provider block in a consuming root module).
#   - location must be a Gov cloud region, e.g. "usgovvirginia" or "usgovarizona" -- Public cloud
#     region names (like "eastus2") are not valid in a Gov subscription.
#   - subnet_id, resource_group_name, and the Key Vault secret reference must all point at
#     resources in the Gov subscription/tenant, not Public.
#   - A Key Vault secret URI in Gov cloud uses the usgovcloudapi.net suffix instead of azure.net,
#     e.g. https://<vault>.vault.usgovcloudapi.net/secrets/<name>/<version> -- already supported by
#     this module's admin_pwd_or_keyvault_secret_id validation.

module "cloud_native_qumulo_government" {
  source = "../"
  # ****************************** QUMULO PROVIDER VARIABLES ********************
  #-----------REQUIRED-------------------
  deployment_name     = "cnq-gov-01"
  location            = "usgovvirginia"
  resource_group_name = "rg-qumulo-gov"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
  vm_type             = "Standard_L8s_v4"

  #------------OPTIONAL------------------
  azure_environment = "usgovernment"
  tags = {
    owner      = "owner"
    department = "department"
    purpose    = "government-example"
  }

  # ***** Qumulo Cluster Variables ******
  #-----------REQUIRED-------------------
  admin_pwd_or_keyvault_secret_id = "https://my-vault.vault.usgovcloudapi.net/secrets/admin-password/00000000000000000000000000000000"
  cluster_name                    = "CNQ-HOT"
  cluster_product_type            = "HOT"
  node_count                      = 3
  deletion_protection             = true
}

output "outputs_cloud_native_qumulo_government" {
  value = module.cloud_native_qumulo_government
}
