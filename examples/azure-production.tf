# Example: a hardened production profile -- multi-AZ, restricted network access, deletion
# protection, private networking for the provider's own control-plane services, and a longer
# create timeout sized for a larger node_count.
#
# This is a starting point, not a fixed recipe: adjust node_count, vm_type, availability_zones,
# and allow_cidrs to match your actual capacity and network requirements.

module "cloud_native_qumulo_production" {
  source = "../"
  # ****************************** QUMULO PROVIDER VARIABLES ********************
  #-----------REQUIRED-------------------
  deployment_name     = "cnq-prod-01"
  location            = "eastus2"
  resource_group_name = "rg-qumulo-prod"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
  vm_type             = "Standard_L16s_v4"

  #------------OPTIONAL------------------
  # Restrict to known client/management networks -- do not leave this null (which defaults to the
  # whole subnet's address prefixes) for a production cluster.
  allow_cidrs         = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones  = ["1", "2", "3"]
  ssh_public_key_path = "~/.ssh/id_rsa.pub"
  tags = {
    owner        = "owner"
    department   = "department"
    purpose      = "production"
    long_running = "true"
  }

  # Keep the provider's own control-plane services (Key Vault, App Configuration) off the
  # public internet.
  disable_appconfig_public_network_access = true
  disable_keyvault_public_network_access  = true

  # ***** Qumulo Cluster Variables ******
  #-----------REQUIRED-------------------
  admin_pwd_or_keyvault_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault_name>/secrets/<secret_name>"
  cluster_name                    = "CNQ-HOT"
  cluster_product_type            = "HOT"
  node_count                      = 6
  deletion_protection             = true

  #------------OPTIONAL------------------
  floating_ip_count = 12
  # Zone-redundant storage for production; requires a region where ZRS is available.
  storage_replication_type = "ZRS"
  # Larger clusters take longer to provision -- raise the create timeout accordingly rather than
  # relying on the wrapper's 30-minute default (provider_timeout_minutes still applies to
  # update/delete unless those are also overridden).
  provider_create_timeout_minutes = 90
}

output "outputs_cloud_native_qumulo_production" {
  value = module.cloud_native_qumulo_production
}
