# Example: deploying cluster nodes on a RHEL marketplace image instead of the default Ubuntu image.
# The provisioner VM is left on the default Ubuntu image -- provisioner_marketplace_image is shown
# commented out below since changing the provisioner's image does not trigger cluster replacement
# and Ubuntu is a fine choice for it regardless of the cluster nodes' OS.
#
# Common RHEL marketplace values (see the provider's Azure Custom Images guide for the current list):
#   RHEL 8 -> sku = "8-lvm-gen2"
#   RHEL 9 -> sku = "9-lvm-gen2"
# publisher/offer are the same ("RedHat" / "RHEL") for both, and version = "latest" resolves to the
# newest published image at apply time.

module "cloud_native_qumulo_rhel" {
  source = "../"
  # ****************************** QUMULO PROVIDER VARIABLES ********************
  #-----------REQUIRED-------------------
  deployment_name     = "cnq-rhel-01"
  location            = "eastus2"
  resource_group_name = "rg-qumulo"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
  vm_type             = "Standard_L8s_v4"

  #------------OPTIONAL------------------
  marketplace_image = [{
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "9-lvm-gen2"
    version   = "latest"
  }]
  # provisioner_marketplace_image = [{
  #   publisher = "RedHat"
  #   offer     = "RHEL"
  #   sku       = "9-lvm-gen2"
  #   version   = "latest"
  # }]

  ssh_public_key_path = "~/.ssh/id_rsa.pub"
  tags = {
    owner      = "owner"
    department = "department"
    purpose    = "rhel-example"
  }

  # ***** Qumulo Cluster Variables ******
  #-----------REQUIRED-------------------
  admin_pwd_or_keyvault_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault_name>/secrets/<secret_name>"
  cluster_name                    = "CNQ-HOT"
  cluster_product_type            = "HOT"
  node_count                      = 3
  deletion_protection             = true
}

output "outputs_cloud_native_qumulo_rhel" {
  value = module.cloud_native_qumulo_rhel
}
