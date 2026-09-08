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

#Intentionally not `ephemeral = true`: this module reads the value (regex-matching it as an ARM
#ID, a Key Vault URI, or a plaintext password, then looking up the vault by name) before ever
#passing it to the provider. That detection/lookup path cannot work with an ephemeral value --
#ephemeral values are only permitted in write-only resource arguments, not in the `name`/`count`
#style arguments this module's Key Vault resolution depends on. sensitive = true already keeps it
#out of logs/plan output and satisfies the provider's write-only admin_password argument.
variable "admin_pwd_or_keyvault_secret_id" {
  type        = string
  sensitive   = true
  description = "Provide either a plaintext administrator password, the resource ID of an Azure Key Vault secret (<key_vault_resource_id>/secrets/<secret_name>), or a Key Vault secret URI (https://<vault>.vault.azure.net/secrets/<secret_name>/<version>). The URI's optional /<version> segment is accepted but ignored -- Terraform always reads the secret's current/latest version, even if an older version is named. This value is write-only, so Terraform never stores it in state, but its current value is resupplied to the provider on every apply that touches this resource (not just creation), since node/vm_type changes must authenticate to the existing cluster with it. It does NOT itself rotate an already-running cluster's password -- use the Qumulo UI or qumulo-cli to change the password after creation, and update the Key Vault secret (or vice versa) any time you do, to keep the two in sync for future applies. WARNING: there is no pre-flight check that this value matches the existing cluster's actual password -- if it has drifted out of sync, an apply that needs to authenticate to an existing cluster (e.g. scaling, vm_type changes) can fail partway through without automatic cleanup. Verify the two match before applying changes to an existing cluster."

  validation {
    condition = (
      # Option A: Valid Azure Key Vault secret ARM resource ID
      can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+/secrets/[^/]+$", var.admin_pwd_or_keyvault_secret_id)) ||

      # Option B: Valid Azure Key Vault secret URI, e.g. https://<vault>.vault.azure.net/secrets/<name>/<version>
      # This is the form shown in the Azure Portal and by `az keyvault secret show`.
      can(regex("^https://[a-zA-Z0-9-]+\\.vault\\.(azure\\.net|usgovcloudapi\\.net)/secrets/[a-zA-Z0-9-]+(/[a-zA-Z0-9]+)?/?$", var.admin_pwd_or_keyvault_secret_id)) ||

      # Option C: Plaintext Password Criteria
      # Must not resemble a URL or resource ID (a common copy-paste mistake that would otherwise be
      # silently treated as a literal password). Azure VMs require 6-72 characters containing at
      # least 3 of: lowercase, uppercase, number, special character.
      (
        !can(regex("^(https?://|/subscriptions/)", var.admin_pwd_or_keyvault_secret_id)) &&
        length(var.admin_pwd_or_keyvault_secret_id) >= 8 &&
        length(var.admin_pwd_or_keyvault_secret_id) <= 72 &&
        (
          (can(regex("[a-z]", var.admin_pwd_or_keyvault_secret_id)) ? 1 : 0) +
          (can(regex("[A-Z]", var.admin_pwd_or_keyvault_secret_id)) ? 1 : 0) +
          (can(regex("[0-9]", var.admin_pwd_or_keyvault_secret_id)) ? 1 : 0) +
          (can(regex("[^a-zA-Z0-9]", var.admin_pwd_or_keyvault_secret_id)) ? 1 : 0)
        ) >= 3
      )
    )
    error_message = "The admin_pwd_or_keyvault_secret_id must be a valid Azure Key Vault secret resource ID (/subscriptions/.../vaults/<vault>/secrets/<secret>), a Key Vault secret URI (https://<vault>.vault.azure.net/secrets/<secret>/<version>), or a plaintext password that is 8-72 characters long containing at least 3 of: lowercase letter, uppercase letter, number, special character. A value starting with http(s):// or /subscriptions/ that doesn't match either reference format is rejected rather than used as a literal password."
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
  description = "Azure subscription ID. Required -- the qumulo provider only falls back to the ARM_SUBSCRIPTION_ID environment variable, not the active Azure CLI context, so `az login` alone is not sufficient. Set this explicitly (or export ARM_SUBSCRIPTION_ID and pass it through as this variable's value)."
  type        = string
  nullable    = false
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

variable "cluster_uuid" {
  description = "OPTIONAL: UUID of an existing Qumulo cluster to import/adopt, for the rare case where the cluster's UUID cannot be auto-recovered. Leave null for new deployments."
  type        = string
  default     = null
  nullable    = true
}

variable "cluster_version" {
  description = "OPTIONAL: Qumulo software version. Defaults to latest. Immutable after creation. Upgrade version via cluster UI/API."
  type        = string
  default     = null
  nullable    = true
}

variable "custom_image_id" {
  description = "OPTIONAL: Custom VM image resource ID for cluster nodes. If omitted, the default Qumulo image (Ubuntu) is used. Mutually exclusive with marketplace_image."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = !(var.custom_image_id != null && var.marketplace_image != null)
    error_message = "Set only one of custom_image_id or marketplace_image for cluster nodes, not both."
  }
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

variable "hooks_apply_watch" {
  description = "OPTIONAL: While a hook is wired, tail the VMs' boot-diagnostics serial logs during `terraform apply` and print the hooks' \"[<hook_name>] ...\" lines into the apply output (needs the az CLI; see hooks-watch.tf). Set false to opt out."
  type        = bool
  default     = true
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

variable "nexus_account_id" {
  description = "OPTIONAL: Qumulo Nexus organization ID to onboard newly-created clusters to. Only relevant when nexus_api_token is set; omit to let the provider auto-resolve the organization from the token's binding."
  type        = number
  default     = null
  nullable    = true
}

variable "nexus_api_token" {
  description = "OPTIONAL: Qumulo Nexus API token. When set, the provider auto-mints nexus_registration_key and onboards new clusters to Nexus Fleet automatically; any value supplied to nexus_registration_key is ignored. Leave null (with nexus_registration_key) to skip Nexus onboarding entirely."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "nexus_registration_key" {
  description = "OPTIONAL: (Deprecated) Qumulo Nexus registration key for remote support. Ignored when nexus_api_token is set on the provider."
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

variable "node_hooks_files" {
  description = "OPTIONAL: Advanced use only. Filenames (relative to the hooks/ directory) spliced into each node's boot script at the pre-run (before first network operation) / post-run (after qumulo-core install) anchors. Runs only on first boot. Use pre_run_files / post_run_files to chain several hooks: their contents are inlined in list order into the single anchor. pre_run_file / post_run_file remain as the single-file forms. override_file replaces the entire node boot script."
  type = object({
    pre_run_file   = optional(string)
    pre_run_files  = optional(list(string))
    post_run_file  = optional(string)
    post_run_files = optional(list(string))
    override_file  = optional(string)
  })

  validation {
    condition = var.node_hooks_files == null || (
      !(var.node_hooks_files.pre_run_file != null && var.node_hooks_files.pre_run_files != null) &&
      !(var.node_hooks_files.post_run_file != null && var.node_hooks_files.post_run_files != null)
    )
    error_message = "Set pre_run_file or pre_run_files, not both (and likewise for post_run); the plural form is the singular's list equivalent."
  }
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
  description = "The default timeout (in minutes) applied to any of create/update/delete not individually overridden by provider_create_timeout_minutes / provider_update_timeout_minutes / provider_delete_timeout_minutes below."
  type        = number
  default     = 30
  nullable    = false
}

variable "provider_create_timeout_minutes" {
  description = "OPTIONAL: Timeout override (in minutes) for cluster creation. Defaults to provider_timeout_minutes if unset. The provider's own built-in default (used only if the whole timeouts block were omitted) is 90 minutes."
  type        = number
  default     = null
  nullable    = true
}

variable "provider_update_timeout_minutes" {
  description = "OPTIONAL: Timeout override (in minutes) for cluster updates (e.g. scaling, vm_type changes). Defaults to provider_timeout_minutes if unset. The provider's own built-in default (used only if the whole timeouts block were omitted) is 60 minutes."
  type        = number
  default     = null
  nullable    = true
}

variable "provider_delete_timeout_minutes" {
  description = "OPTIONAL: Timeout override (in minutes) for cluster deletion. Defaults to provider_timeout_minutes if unset. The provider's own built-in default (used only if the whole timeouts block were omitted) is 30 minutes."
  type        = number
  default     = null
  nullable    = true
}

variable "provisioner_custom_image_id" {
  description = "OPTIONAL: Custom VM image resource ID for the provisioner instance. Defaults to the default Qumulo image. Mutually exclusive with provisioner_marketplace_image."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = !(var.provisioner_custom_image_id != null && var.provisioner_marketplace_image != null)
    error_message = "Set only one of provisioner_custom_image_id or provisioner_marketplace_image, not both."
  }
}

variable "provisioner_hooks_files" {
  description = "OPTIONAL: Advanced use only. Filenames (relative to the hooks/ directory) spliced into the provisioner's boot script at pre_run_file (after deployment variables are set) / post_run_file (after the cluster is formed and configured) anchors. override_file replaces the entire provisioner boot script. Use pre_run_files / post_run_files to chain several hooks: their contents are inlined in list order into the single anchor."
  type = object({
    pre_run_file   = optional(string)
    pre_run_files  = optional(list(string))
    post_run_file  = optional(string)
    post_run_files = optional(list(string))
    override_file  = optional(string)
  })

  validation {
    condition = var.provisioner_hooks_files == null || (
      !(var.provisioner_hooks_files.pre_run_file != null && var.provisioner_hooks_files.pre_run_files != null) &&
      !(var.provisioner_hooks_files.post_run_file != null && var.provisioner_hooks_files.post_run_files != null)
    )
    error_message = "Set pre_run_file or pre_run_files, not both (and likewise for post_run); the plural form is the singular's list equivalent."
  }
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
  description = "Seed name for this deployment's Azure resource group. An immutable random suffix is always appended (e.g. \"myrg-h12g9v-rg\", or see resource_group_name_suffix to customize the trailing \"-rg\" label) so every deployment gets its own dedicated resource group -- this is NOT the literal resource group name. WARNING: never point two Qumulo clusters at the same resource group, and never place any other VM/NIC into the resource group this deployment creates. Azure floating IPs are attached as secondary IP configurations on node NICs, and the floating-IP reconciler scopes by the ENTIRE resource group with no cluster filter -- it will strip secondary IPs from any NIC in the resource group it doesn't recognize as its own. Sharing a resource group causes clusters (or any other floating/secondary-IP-bearing VM) to fight over floating IPs indefinitely, which has been observed firsthand as one cluster stealing another's floating IPs on boot."
  type        = string
  nullable    = false
}

variable "resource_group_name_suffix" {
  description = "OPTIONAL: Trailing label appended after the random uniqueness suffix in the auto-generated resource group name (default \"-rg\", e.g. \"myrg-h12g9v-rg\"). Purely cosmetic -- freeform, set to whatever matches your naming convention (e.g. \"-westus2\", or \"\" for none). Does NOT affect the uniqueness guarantee: the random suffix between resource_group_name and this label is always present and is not customizable, since it's the mechanism that keeps every deployment's resource group dedicated (see main.tf)."
  type        = string
  default     = "-rg"
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
  description = "Azure VM size for cluster nodes. Only L-series storage-optimized VMs are supported (e.g. Standard_L8s_v4)."
  type        = string
  nullable    = false
}
