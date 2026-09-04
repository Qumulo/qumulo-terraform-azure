#MIT License

#Copyright (c) 2026 Qumulo, Inc.

#Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the Software), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

# **** Version 1.0 (Azure) ****

locals {
  # An Azure subnet resource ID is of the form:
  # /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>
  subnet_id_parts = regex(
    "^/subscriptions/(?P<subscription_id>[0-9a-fA-F-]+)/resourceGroups/(?P<resource_group>[^/]+)/providers/Microsoft\\.Network/virtualNetworks/(?P<vnet_name>[^/]+)/subnets/(?P<subnet_name>[^/]+)$",
    var.subnet_id
  )
}

#Check that the subnet has the service endpoints the Qumulo provider requires
data "azurerm_subnet" "selected" {
  name                 = local.subnet_id_parts.subnet_name
  virtual_network_name = local.subnet_id_parts.vnet_name
  resource_group_name  = local.subnet_id_parts.resource_group

  lifecycle {
    postcondition {
      condition     = contains([for se in self.service_endpoint : se.service], "Microsoft.KeyVault") && contains([for se in self.service_endpoint : se.service], "Microsoft.Storage")
      error_message = "Subnet ${var.subnet_id} is missing required service endpoints. Enable Microsoft.KeyVault and Microsoft.Storage service endpoints on the subnet before deploying."
    }
  }
}

locals {
  allow_cidrs    = var.allow_cidrs == null ? data.azurerm_subnet.selected.address_prefixes : var.allow_cidrs
  ssh_public_key = var.ssh_public_key_path == null ? null : file(pathexpand(var.ssh_public_key_path))

  # node_hooks_files/provisioner_hooks_files default to null as a whole object; fall back to an
  # all-null object so main.tf can safely dereference .pre_run_file/.post_run_file/.override_file
  # below even when the variable is omitted entirely.
  node_hooks_files_safe        = var.node_hooks_files == null ? { pre_run_file = null, post_run_file = null, override_file = null } : var.node_hooks_files
  provisioner_hooks_files_safe = var.provisioner_hooks_files == null ? { pre_run_file = null, post_run_file = null, override_file = null } : var.provisioner_hooks_files
}

#Each Qumulo cluster MUST have its own dedicated Azure resource group. Azure floating IPs are attached as
#secondary IP configurations on node NICs, and Qumulo's floating-IP reconciler for Terraform-deployed
#("customer-managed") clusters scopes by the ENTIRE resource group, not by cluster: on every reconcile
#cycle, each cluster's leader enumerates every VM/NIC in the resource group and strips secondary IP
#configurations from any NIC it doesn't recognize as one of its own nodes. If two clusters (or any other
#VM that happens to carry a secondary IP) share a resource group, they will fight over floating IPs
#indefinitely -- this has been observed firsthand as one cluster stealing another's floating IPs on boot.
#To make this impossible to hit by accident, resource_group_name is treated as a seed: an immutable random
#suffix is appended below to guarantee every deployment gets its own resource group, the same way
#deployment_name becomes deployment_unique_name. THIS RANDOM SUFFIX IS NOT OPTIONAL -- there is no
#supported way to disable it, and do not attempt to force two deployments to share a resource group.
#The trailing label after the random suffix (default "-rg") is purely cosmetic and IS customizable via
#resource_group_name_suffix, e.g. for teams whose naming convention prefers a region code or nothing at
#all -- see variables.tf. Changing it has no effect on the uniqueness guarantee above.
#With use_literal_resource_group_name, no suffix resource exists: the caller
#names the group exactly (typically pre-created, so RBAC and policy exemptions
#can be granted before the first apply; the provider creates it if absent).
#The dedicated-group contract above still applies -- one cluster per group.
resource "random_string" "resource_group_suffix" {
  count = var.use_literal_resource_group_name ? 0 : 1

  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false

  keepers = {
    resource_group_name = var.resource_group_name
  }

  lifecycle {
    ignore_changes = all
  }
}

moved {
  from = random_string.resource_group_suffix
  to   = random_string.resource_group_suffix[0]
}

locals {
  resource_group_unique_name = var.use_literal_resource_group_name ? var.resource_group_name : "${var.resource_group_name}-${random_string.resource_group_suffix[0].result}${var.resource_group_name_suffix}"
}

#This resource reads an Azure Key Vault secret if a secret resource ID is provided, or accepts a text based admin password.  One or the other must be provided.
#A best practice is to put your password in Azure Key Vault. Note, you will need to update it in Key Vault if you change the Admin Password via the Qumulo Core UI/CLI/API.
#Text based password input is treated as sensitive and is provided for environments where another vault solution is being used outside of Azure or for simple test environments.
module "secrets" {
  source = "./modules/secrets"

  admin_pwd_or_keyvault_secret_id = var.admin_pwd_or_keyvault_secret_id
}

#This resource builds the Qumulo Cluster consisting of Azure VMs, managed disks/storage accounts, a resource group, managed identities, and (optionally) a Key Vault.
#Network security groups are built for the cluster and provisioning instance.
resource "qumulo_filesystem_azure" "cluster" {
  provider = qumulo

  admin_password                          = module.secrets.resolved_password
  allow_cidrs                             = local.allow_cidrs
  availability_zones                      = var.availability_zones
  cluster_fqdn                            = var.cluster_fqdn
  cluster_name                            = var.cluster_name
  cluster_node_identity_id                = var.cluster_node_identity_id
  cluster_product_type                    = var.cluster_product_type
  cluster_uuid                            = var.cluster_uuid
  cluster_version                         = var.cluster_version
  custom_image_id                         = var.custom_image_id
  deletion_protection                     = var.deletion_protection
  deployment_name                         = var.deployment_name
  disable_appconfig_public_network_access = var.disable_appconfig_public_network_access
  disable_keyvault_public_network_access  = var.disable_keyvault_public_network_access
  floating_ip_count                       = var.floating_ip_count
  key_vault_id                            = var.key_vault_id
  location                                = var.location
  marketplace_image                       = var.marketplace_image
  naming                                  = var.naming
  networking_mode                         = var.networking_mode
  nexus_registration_key                  = var.nexus_registration_key
  node_count                              = var.node_count
  nsg_allow_ingress_icmp                  = var.nsg_allow_ingress_icmp
  persistent_storage_resource_group       = var.persistent_storage_resource_group
  private_link_appconfig_dns_zone_id      = var.private_link_appconfig_dns_zone_id
  private_link_keyvault_dns_zone_id       = var.private_link_keyvault_dns_zone_id
  provisioner_custom_image_id             = var.provisioner_custom_image_id
  provisioner_identity_id                 = var.provisioner_identity_id
  provisioner_marketplace_image           = var.provisioner_marketplace_image
  provisioner_vm_type                     = var.provisioner_vm_type
  resource_group_name                     = local.resource_group_unique_name
  soft_capacity_limit_tb                  = var.soft_capacity_limit_tb
  ssh_public_key                          = local.ssh_public_key
  storage_class                           = var.storage_class
  storage_replication_type                = var.storage_replication_type
  subnet_id                               = var.subnet_id
  tags                                    = var.tags
  vm_type                                 = var.vm_type

  node_hooks = {
    pre_run  = local.node_hooks_files_safe.pre_run_file == null ? null : file("${path.module}/hooks/${local.node_hooks_files_safe.pre_run_file}")
    post_run = local.node_hooks_files_safe.post_run_file == null ? null : file("${path.module}/hooks/${local.node_hooks_files_safe.post_run_file}")
    override = local.node_hooks_files_safe.override_file == null ? null : file("${path.module}/hooks/${local.node_hooks_files_safe.override_file}")
  }
  provisioner_hooks = {
    pre_run  = local.provisioner_hooks_files_safe.pre_run_file == null ? null : file("${path.module}/hooks/${local.provisioner_hooks_files_safe.pre_run_file}")
    post_run = local.provisioner_hooks_files_safe.post_run_file == null ? null : file("${path.module}/hooks/${local.provisioner_hooks_files_safe.post_run_file}")
    override = local.provisioner_hooks_files_safe.override_file == null ? null : file("${path.module}/hooks/${local.provisioner_hooks_files_safe.override_file}")
  }

  timeouts {
    create = "${tostring(coalesce(var.provider_create_timeout_minutes, var.provider_timeout_minutes))}m"
    delete = "${tostring(coalesce(var.provider_delete_timeout_minutes, var.provider_timeout_minutes))}m"
    update = "${tostring(coalesce(var.provider_update_timeout_minutes, var.provider_timeout_minutes))}m"
  }
}
