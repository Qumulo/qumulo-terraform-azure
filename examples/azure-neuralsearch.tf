# Example: cluster plus an optional Qumulo NeuralSearch appliance.
#
# The appliance is one VM in the cluster's VNet and subnet, placed in its own resource group
# (<resource_group_name>-search). The subnet needs outbound HTTPS (for example through a NAT
# gateway) to qumulo-neuralsearch.s3.us-west-2.amazonaws.com, get.docker.com, download.docker.com,
# public.ecr.aws, and the Ubuntu package mirrors, or the apply waits until the provider timeout.
# The web UI is served on TCP 443 at the appliance's private IP. See README "NeuralSearch (optional)"
# for the first-boot setup wizard.

module "cloud_native_qumulo_neuralsearch" {
  source = "../"
  # ****************************** QUMULO PROVIDER VARIABLES ********************
  #-----------REQUIRED-------------------
  deployment_name       = "cnq-search-01"
  location              = "eastus2"
  resource_group_name   = "rg-qumulo-search"
  subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
  vm_type               = "Standard_L8s_v4"
  azure_subscription_id = "00000000-0000-0000-0000-000000000000"

  # ***** Qumulo Cluster Variables ******
  #-----------REQUIRED-------------------
  admin_pwd_or_keyvault_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault_name>/secrets/<secret_name>"
  cluster_name                    = "CNQ-SEARCH"
  cluster_product_type            = "HOT"
  node_count                      = 3
  deletion_protection             = true

  #------------NEURALSEARCH------------------
  neuralsearch_provision = true
  # Null keeps the VirtualNetwork service tag. Setting CIDRs replaces it.
  neuralsearch_allow_cidrs = ["10.0.0.0/8"]
  # Null keeps the provider default, Standard_D16as_v5.
  neuralsearch_vm_type = null
}

output "neuralsearch_ui_url" {
  value = module.cloud_native_qumulo_neuralsearch.neuralsearch_ui_url
}
