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

variable "admin_pwd_or_keyvault_secret_id" {
  type        = string
  sensitive   = true
  description = "Provide either a plaintext administrator password or the resource ID of an Azure Key Vault secret, in the form <key_vault_resource_id>/secrets/<secret_name>."

  validation {
    condition = (
      # Option A: Valid Azure Key Vault secret resource ID
      can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+/secrets/[^/]+$", var.admin_pwd_or_keyvault_secret_id)) ||

      # Option B: Plaintext Password Criteria
      # Azure requires 8-128 characters containing at least 3 of: lowercase, uppercase, number, special character.
      (
        length(var.admin_pwd_or_keyvault_secret_id) >= 8 &&
        length(var.admin_pwd_or_keyvault_secret_id) <= 128 &&
        (
          (can(regex("[a-z]", var.admin_pwd_or_keyvault_secret_id)) ? 1 : 0) +
          (can(regex("[A-Z]", var.admin_pwd_or_keyvault_secret_id)) ? 1 : 0) +
          (can(regex("[0-9]", var.admin_pwd_or_keyvault_secret_id)) ? 1 : 0) +
          (can(regex("[^a-zA-Z0-9]", var.admin_pwd_or_keyvault_secret_id)) ? 1 : 0)
        ) >= 3
      )
    )
    error_message = "The admin_pwd_or_keyvault_secret_id must be either a valid Azure Key Vault secret resource ID (/subscriptions/.../vaults/<vault>/secrets/<secret>), or a password that is 8-128 characters long containing at least 3 of: lowercase letter, uppercase letter, number, special character."
  }
}

variable "allow_cidrs" {
  description = "OPTIONAL: CIDR blocks allowed to access the cluster. Defaults to the cluster subnet's address prefixes if not provided."
  type        = list(string)
  default     = null
  nullable    = true
}

variable "availability_zones" {
  description = "OPTIONAL: Availability zones for deployment, e.g. [\"1\", \"2\", \"3\"]. Omit for zoneless regions. Zone support is validated dynamically by the provider."
  type        = list(string)
  default     = null
  nullable    = true
}

variable "azure_environment" {
  description = "OPTIONAL: Azure cloud environment for the qumulo provider."
  type        = string
  default     = "public"
  nullable    = false

  validation {
    condition     = contains(["public", "usgovernment"], var.azure_environment)
    error_message = "azure_environment must be either \"public\" or \"usgovernment\"."
  }
}

variable "azure_subscription_id" {
  description = "OPTIONAL: Azure subscription ID. If omitted, resolved from the ARM_SUBSCRIPTION_ID environment variable or the active Azure CLI context."
  type        = string
  default     = null
  nullable    = true
}

variable "cluster_fqdn" {
  description = "OPTIONAL: Fully qualified domain name for Qumulo Core authoritative DNS. When set, the cluster answers DNS queries with floating IPs."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.cluster_fqdn == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.cluster_fqdn))
    error_message = "The fqdn must use lowercase, start and end with letters only, and may contain . and -"
  }
}

variable "cluster_name" {
  description = "Name of the Qumulo cluster as it appears in qfsd and the UI (2-15 characters; case preserved; dash allowed if not first or last character)."
  type        = string
  nullable    = false
}

variable "cluster_node_identity_id" {
  description = "OPTIONAL: Resource ID of a user-assigned managed identity for cluster nodes. If omitted, the provider creates one."
  type        = string
  default     = null
  nullable    = true
}

variable "cluster_product_type" {
  description = "Cluster storage product type (immutable after creation). HOT: Optimized for frequently accessed data. COLD: Optimized for archival/infrequently accessed data."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["HOT", "COLD"], var.cluster_product_type)
    error_message = "cluster_product_type must be either \"HOT\" or \"COLD\"."
  }
}

variable "cluster_version" {
  description = "OPTIONAL: Qumulo software version. Defaults to latest. Immutable after creation. Upgrade version via cluster UI/API."
  type        = string
  default     = null
  nullable    = true
}

variable "custom_image_id" {
  description = "OPTIONAL: Custom VM image resource ID for cluster nodes. If omitted, the default Qumulo image (Ubuntu) is used."
  type        = string
  default     = null
  nullable    = true
}

variable "deletion_protection" {
  description = "Protects the cluster's VMs and storage accounts from deletion with CanNotDelete management locks."
  type        = bool
  default     = true
}

variable "deployment_name" {
  description = "Lowercase seed for Azure resource names (2-15 characters: lowercase letters, digits, interior hyphens)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,13}[a-z0-9])?$", var.deployment_name))
    error_message = "deployment_name must be 2-15 characters: lowercase letters, digits, and interior hyphens only."
  }
}

variable "disable_appconfig_public_network_access" {
  description = "OPTIONAL: Disable public network access to the App Configuration instance the provider creates."
  type        = bool
  default     = false
}

variable "disable_keyvault_public_network_access" {
  description = "OPTIONAL: Disable public network access to the Key Vault the provider creates or uses."
  type        = bool
  default     = false
}

variable "floating_ip_count" {
  description = "OPTIONAL: Number of floating IPs to assign to the cluster. Must be 0 (disabled) or between 3 and 100. Requires networking_mode \"host_managed\". Once a count has been applied, omitting this attribute keeps the previous value -- set it to 0 explicitly to remove floating IPs."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.floating_ip_count == 0 || (var.floating_ip_count >= 3 && var.floating_ip_count <= 100)
    error_message = "floating_ip_count must be 0, or between 3 and 100."
  }
}

variable "key_vault_id" {
  description = "OPTIONAL: Full Azure resource ID of a customer-managed Key Vault. If omitted, the provider creates one."
  type        = string
  default     = null
  nullable    = true
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
  nullable    = false
}

variable "marketplace_image" {
  description = "OPTIONAL: Azure Marketplace image specification for cluster nodes."
  type = list(object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  }))
  default  = null
  nullable = true
}

variable "naming" {
  description = "OPTIONAL: Custom naming templates for Azure resources."
  type = list(object({
    storage_account = optional(string)
    vm_name         = optional(string)
  }))
  default  = null
  nullable = true
}

variable "networking_mode" {
  description = "OPTIONAL: Network management mode for cluster nodes (\"host_managed\" default or \"qumulo_managed\")."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.networking_mode == null || contains(["host_managed", "qumulo_managed"], var.networking_mode)
    error_message = "networking_mode must be null, \"host_managed\", or \"qumulo_managed\"."
  }
}

variable "nexus_registration_key" {
  description = "OPTIONAL: (Deprecated) Qumulo Nexus registration key for remote support."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "node_count" {
  description = "Number of nodes in the cluster. Valid values: 1 (single node), or 3-24. 2 is not supported, and 4 requires a single availability zone."
  type        = number
  nullable    = false
}

variable "node_hooks" {
  description = "OPTIONAL: Advanced use only. Shell spliced into each node's boot script at pre_run (before first network operation) / post_run (after qumulo-core install) anchors. Runs only on first boot. override replaces the entire node boot script."
  type = object({
    pre_run  = optional(string)
    post_run = optional(string)
    override = optional(string)
  })
  default  = null
  nullable = true
}

variable "nsg_allow_ingress_icmp" {
  description = "OPTIONAL: Enable ICMP ingress in the NSG rules the provider creates, for network diagnostics."
  type        = bool
  default     = false
}

variable "persistent_storage_resource_group" {
  description = "OPTIONAL: Resource group containing persistent storage accounts and Key Vault, if different from resource_group_name."
  type        = string
  default     = null
  nullable    = true
}

variable "private_link_appconfig_dns_zone_id" {
  description = "OPTIONAL: Resource ID of the privatelink.azconfig.io private DNS zone."
  type        = string
  default     = null
  nullable    = true
}

variable "private_link_keyvault_dns_zone_id" {
  description = "OPTIONAL: Resource ID of the privatelink.vaultcore.azure.net private DNS zone."
  type        = string
  default     = null
  nullable    = true
}

variable "provider_timeout_minutes" {
  description = "The total time after which Terraform will abandon the provider deployment of the Qumulo cluster and timeout. In minutes."
  type        = number
  default     = 30
  nullable    = false
}

variable "provisioner_custom_image_id" {
  description = "OPTIONAL: Custom VM image resource ID for the provisioner instance. Defaults to the default Qumulo image."
  type        = string
  default     = null
  nullable    = true
}

variable "provisioner_hooks" {
  description = "OPTIONAL: Advanced use only. Shell spliced into the provisioner's boot script at pre_run (after deployment variables are set) / post_run (after the cluster is formed and configured) anchors. override replaces the entire provisioner boot script."
  type = object({
    pre_run  = optional(string)
    post_run = optional(string)
    override = optional(string)
  })
  default  = null
  nullable = true
}

variable "provisioner_identity_id" {
  description = "OPTIONAL: Resource ID of a user-assigned managed identity for the provisioner VM. If omitted, the provider creates one."
  type        = string
  default     = null
  nullable    = true
}

variable "provisioner_marketplace_image" {
  description = "OPTIONAL: Azure Marketplace image specification for the provisioner VM."
  type = list(object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  }))
  default  = null
  nullable = true
}

variable "provisioner_vm_type" {
  description = "OPTIONAL: Azure VM size for the provisioner instance (used during deploy operations). Defaults to the provider's built-in default."
  type        = string
  default     = null
  nullable    = true
}

variable "resource_group_name" {
  description = "Azure resource group name for the cluster. Created by the provider if it does not already exist."
  type        = string
  nullable    = false
}

variable "soft_capacity_limit_tb" {
  description = "OPTIONAL: Soft capacity limit in TB (50 to 10000). Default is 500TB. Can be increased to add storage, but cannot be decreased. It's like a quota, unused capacity is not billed."
  type        = number
  default     = 500
  nullable    = false
}

variable "ssh_public_key_path" {
  description = "OPTIONAL: Path to a local SSH public key file for SSH access to cluster nodes, e.g. \"~/.ssh/id_rsa.pub\". The file's contents are read and passed to the provider; \"~\" is expanded to the home directory. Do not set this to the key content itself."
  type        = string
  default     = null
  nullable    = true
}

variable "storage_class" {
  description = "OPTIONAL: Storage backing the cluster's persistent data. HOT supports STANDARD and INTELLIGENT_TIERING. Defaults to the provider's built-in default for the chosen cluster_product_type."
  type        = string
  default     = null
  nullable    = true
}

variable "storage_replication_type" {
  description = "OPTIONAL: Azure storage replication type (immutable after creation). LRS or ZRS."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.storage_replication_type == null || contains(["LRS", "ZRS"], var.storage_replication_type)
    error_message = "storage_replication_type must be null, \"LRS\", or \"ZRS\"."
  }
}

variable "subnet_id" {
  description = "Full Azure resource ID of the subnet. The cluster's storage accounts are restricted to this subnet. The subnet must have the Microsoft.KeyVault and Microsoft.Storage service endpoints enabled."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a full Azure subnet resource ID of the form /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
}

variable "tags" {
  description = "OPTIONAL: Tags to apply to all Azure resources created for this cluster."
  type        = map(string)
  default     = null
  nullable    = true
}

variable "vm_type" {
  description = "Azure VM size for cluster nodes. Only L-series storage-optimized VMs are supported (e.g. Standard_L8s_v3)."
  type        = string
  nullable    = false
}
