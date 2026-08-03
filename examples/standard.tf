module "cloud_native_qumulo" {
  source = "../"
  # ****************************** QUMULO PROVIDER VARIABLES ********************
  #-----------REQUIRED-------------------
  deployment_name     = "cnq-deploy-01"
  location            = "eastus2"
  resource_group_name = "rg-qumulo"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
  vm_type             = "Standard_L8s_v3"

  #------------OPTIONAL------------------
  allow_cidrs                 = null
  availability_zones          = ["1", "2", "3"]
  azure_environment           = "public"
  azure_subscription_id       = null
  cluster_node_identity_id    = null
  custom_image_id             = null
  key_vault_id                = null
  provisioner_custom_image_id = null
  provisioner_identity_id     = null
  provisioner_vm_type         = null
  ssh_public_key_path         = null
  tags = {
    owner        = "owner"
    department   = "department"
    purpose      = "purpose"
    long_running = "true"
  }

  # ***** Qumulo Cluster Variables ******
  #-----------REQUIRED-------------------
  admin_pwd_or_keyvault_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault_name>/secrets/<secret_name>"
  cluster_name                    = "CNQ-HOT"
  cluster_product_type            = "HOT"
  node_count                      = 3
  deletion_protection             = true

  #------------OPTIONAL------------------
  cluster_version          = null
  floating_ip_count        = 3
  nexus_registration_key   = null
  provider_timeout_minutes = 30
  storage_class            = null
  storage_replication_type = null
  soft_capacity_limit_tb   = null
}

output "outputs_cloud_native_qumulo" {
  value = module.cloud_native_qumulo
}
