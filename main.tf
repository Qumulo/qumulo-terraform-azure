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

  # node_hooks_files/provisioner_hooks_files default to null as a whole object; normalize the
  # single-file and list forms into one list per anchor, in inline order. Each entry's content
  # gets a banner naming its file so the anchors in the rendered boot script stay navigable.
  hooks_files_none             = { pre_run_file = null, pre_run_files = null, post_run_file = null, post_run_files = null, override_file = null }
  node_hooks_files_safe        = var.node_hooks_files == null ? local.hooks_files_none : var.node_hooks_files
  provisioner_hooks_files_safe = var.provisioner_hooks_files == null ? local.hooks_files_none : var.provisioner_hooks_files

  node_pre_run_hook_files         = local.node_hooks_files_safe.pre_run_files != null ? local.node_hooks_files_safe.pre_run_files : (local.node_hooks_files_safe.pre_run_file == null ? [] : [local.node_hooks_files_safe.pre_run_file])
  node_post_run_hook_files        = local.node_hooks_files_safe.post_run_files != null ? local.node_hooks_files_safe.post_run_files : (local.node_hooks_files_safe.post_run_file == null ? [] : [local.node_hooks_files_safe.post_run_file])
  provisioner_pre_run_hook_files  = local.provisioner_hooks_files_safe.pre_run_files != null ? local.provisioner_hooks_files_safe.pre_run_files : (local.provisioner_hooks_files_safe.pre_run_file == null ? [] : [local.provisioner_hooks_files_safe.pre_run_file])
  provisioner_post_run_hook_files = local.provisioner_hooks_files_safe.post_run_files != null ? local.provisioner_hooks_files_safe.post_run_files : (local.provisioner_hooks_files_safe.post_run_file == null ? [] : [local.provisioner_hooks_files_safe.post_run_file])

  node_pre_run_hook_content         = length(local.node_pre_run_hook_files) == 0 ? null : join("\n", [for f in local.node_pre_run_hook_files : "# --- hooks/${f} ---\n${file("${path.module}/hooks/${f}")}"])
  node_post_run_hook_content        = length(local.node_post_run_hook_files) == 0 ? null : join("\n", [for f in local.node_post_run_hook_files : "# --- hooks/${f} ---\n${file("${path.module}/hooks/${f}")}"])
  provisioner_pre_run_hook_content  = length(local.provisioner_pre_run_hook_files) == 0 ? null : join("\n", [for f in local.provisioner_pre_run_hook_files : "# --- hooks/${f} ---\n${file("${path.module}/hooks/${f}")}"])
  provisioner_post_run_hook_content = length(local.provisioner_post_run_hook_files) == 0 ? null : join("\n", [for f in local.provisioner_post_run_hook_files : "# --- hooks/${f} ---\n${file("${path.module}/hooks/${f}")}"])

  #Console log tag of each wired hook (hooks/readme.md, "Hook contract"), for hooks-watch.tf.
  hook_watch_tags = distinct([
    for f in concat(local.node_pre_run_hook_files, local.node_post_run_hook_files, local.provisioner_pre_run_hook_files, local.provisioner_post_run_hook_files) :
    replace(trimsuffix(basename(f), ".sh"), "-", "_")
  ])
}

#resource_group_name is used exactly as given. Both paths work: let the provider create the
#group, or pre-create it (with key_vault_id and other BYO resources) so RBAC grants and policy
#exemptions can exist before the first apply. Do not share the group with any other VMs. On
#Qumulo Core versions below 7.10.1 that is a hard requirement: the floating-IP reconciler on
#those versions strips secondary IPs from every NIC in the group it does not recognize.
#7.10.1 and later touch only addresses the cluster owns.
locals {
  resource_group_unique_name = var.resource_group_name

  # Sort keys make the version comparison in the check below lexicographic-safe (7.9 < 7.10).
  # The resource's cluster_version is the resolved version, covering the auto-selected-latest
  # case: the provider resolves it during plan, so the warning appears at plan time; if it
  # were ever unknown at plan, Terraform evaluates the check at the end of apply instead.
  # An unparseable version (dev builds) skips the warning via the null key.
  fip_reconciler_scoped_version = "7.10.1"
  fip_min_version_key           = join(".", formatlist("%05d", split(".", local.fip_reconciler_scoped_version)))
  cluster_version_key           = try(join(".", formatlist("%05d", slice(split(".", qumulo_filesystem_azure.cluster.cluster_version), 0, 3))), null)
}

check "floating_ip_reconciler_scope" {
  assert {
    condition = (
      local.cluster_version_key == null ||
      sort([local.cluster_version_key, local.fip_min_version_key])[0] == local.fip_min_version_key
    )
    error_message = "Qumulo Core ${qumulo_filesystem_azure.cluster.cluster_version} is below ${local.fip_reconciler_scoped_version}. On these versions the floating-IP reconciler strips secondary IP configurations from every NIC in resource group '${var.resource_group_name}' that it does not recognize as a cluster node. Keep this resource group dedicated to this deployment: no other clusters and no other VMs."
  }
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
  create_appconfig_private_endpoint       = var.create_appconfig_private_endpoint
  create_keyvault_private_endpoint        = var.create_keyvault_private_endpoint
  create_storage_private_endpoint         = var.create_storage_private_endpoint
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
    pre_run  = local.node_pre_run_hook_content
    post_run = local.node_post_run_hook_content
    override = local.node_hooks_files_safe.override_file == null ? null : file("${path.module}/hooks/${local.node_hooks_files_safe.override_file}")
  }
  provisioner_hooks = {
    pre_run  = local.provisioner_pre_run_hook_content
    post_run = local.provisioner_post_run_hook_content
    override = local.provisioner_hooks_files_safe.override_file == null ? null : file("${path.module}/hooks/${local.provisioner_hooks_files_safe.override_file}")
  }

  timeouts {
    create = "${tostring(coalesce(var.provider_create_timeout_minutes, var.provider_timeout_minutes))}m"
    delete = "${tostring(coalesce(var.provider_delete_timeout_minutes, var.provider_timeout_minutes))}m"
    update = "${tostring(coalesce(var.provider_update_timeout_minutes, var.provider_timeout_minutes))}m"
  }

  lifecycle {
    #Chained hooks are inlined into ONE bash boot script per role: every pre/post hook
    #must be a bash fragment that stays valid when merged (see hooks/readme.md, and
    #tools/validate-hooks.sh for a merged syntax check). A shebang marks a standalone
    #script in some other dialect, which cannot be spliced mid-file.
    precondition {
      condition = alltrue([
        for f in concat(
          local.node_pre_run_hook_files, local.node_post_run_hook_files,
          local.provisioner_pre_run_hook_files, local.provisioner_post_run_hook_files,
        ) : endswith(f, ".sh") && !startswith(file("${path.module}/hooks/${f}"), "#!")
      ])
      error_message = "Every chained pre_run/post_run hook must be a .sh bash fragment without a shebang line: hooks are concatenated into a single bash boot script and must be valid when merged (hooks/readme.md documents the contract; override_file is exempt). Check the merge with tools/validate-hooks.sh."
    }
  }
}
