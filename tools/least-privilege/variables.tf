variable "admin_password_key_vault_id" {
  description = "OPTIONAL: Resource ID of the Key Vault holding the cluster admin password, needed only when admin_pwd_or_keyvault_secret_id is a secret URI (https://<vault>.vault.azure.net/secrets/...), which does not name the vault's resource group. The resource-ID form of the secret needs no help."
  type        = string
  default     = null

  validation {
    condition     = var.admin_password_key_vault_id != null || var.admin_pwd_or_keyvault_secret_id == null || !startswith(var.admin_pwd_or_keyvault_secret_id, "https://")
    error_message = "admin_pwd_or_keyvault_secret_id is a Key Vault secret URI, which does not carry the vault's resource group. Set admin_password_key_vault_id to that vault's resource ID so the deployer can be granted read access to the secret."
  }
}

variable "admin_pwd_or_keyvault_secret_id" {
  description = "OPTIONAL: The wrapper's admin_pwd_or_keyvault_secret_id. When it references a Key Vault secret, the deployer is granted read access to it (Key Vault Secrets User on the secret, or a Get access policy on a vault that uses access policies). A plaintext password grants nothing and is not used."
  type        = string
  default     = null
  sensitive   = true
}

variable "azure_subscription_id" {
  description = "Subscription the deployment lands in."
  type        = string
  nullable    = false
}

variable "location" {
  description = "Azure region for the resource group and managed identities."
  type        = string
  nullable    = false
}

variable "resource_group_name" {
  description = "The deployment's resource group -- the same value passed to the wrapper's resource_group_name. Created here unless create_resource_group is false."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name)) && !endswith(var.resource_group_name, ".")
    error_message = "resource_group_name must be a valid Azure resource group name: 1-90 characters of letters, digits, periods, underscores, hyphens, or parentheses, not ending in a period."
  }
}

variable "create_resource_group" {
  description = "Create the resource group here (true) or reference one that already exists (false)."
  type        = bool
  default     = true
}

variable "subnet_id" {
  description = "Full resource ID of the cluster subnet -- the same value passed to the wrapper's subnet_id. Network join grants are scoped to its virtual network."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a full subnet resource ID."
  }
}

variable "deployer_principal_id" {
  description = "OPTIONAL: Object ID of an existing principal to use as the deployer (a user, service principal, or the managed identity of a runner VM). When null, the default, this Terraform creates a user-assigned managed identity named <resource_group_name>-deployer instead -- attach it to the terraform runner VM (see the deployer_identity output)."
  type        = string
  default     = null
}

variable "deployer_principal_type" {
  description = "Principal type of deployer_principal_id: User, Group, or ServicePrincipal (managed identities are ServicePrincipal)."
  type        = string
  default     = "User"

  validation {
    condition     = contains(["User", "Group", "ServicePrincipal"], var.deployer_principal_type)
    error_message = "deployer_principal_type must be User, Group, or ServicePrincipal."
  }
}

variable "deletion_protection" {
  description = "Grant the lock actions the provider needs when the wrapper's deletion_protection is enabled (management locks on VMs and storage accounts)."
  type        = bool
  default     = false
}

variable "key_vault_id" {
  description = "OPTIONAL: Resource ID of a customer-managed Key Vault (the wrapper's key_vault_id). Key Vault grants are scoped to it instead of the deployment resource group."
  type        = string
  default     = null
}

variable "custom_image_id" {
  description = "OPTIONAL: Custom VM image resource ID for cluster nodes (the wrapper's custom_image_id, which also supplies the provisioner's image -- there is no separate provisioner_custom_image_id). The deployer is granted Reader on the image (for a Compute Gallery image, on the whole gallery) so VMs can be created from it and from later images in the same gallery."
  type        = string
  default     = null
}

variable "persistent_storage_resource_group" {
  description = "OPTIONAL: Resource group holding persistent storage accounts when it differs from resource_group_name. Named to match the wrapper variable so the wrapper's terraform.tfvars supplies it directly. Must already exist. Deployer and node grants are extended to it."
  type        = string
  default     = null
}

variable "blob_private_dns_zone_id" {
  description = "OPTIONAL: Resource ID of the blob privatelink DNS zone the wrapper writes records into. Named to match the wrapper variable so the wrapper's terraform.tfvars supplies it directly. Grants the deployer Private DNS Zone Contributor on the zone."
  type        = string
  default     = null
}

variable "keyvault_private_dns_zone_id" {
  description = "OPTIONAL: Resource ID of the Key Vault privatelink DNS zone the wrapper writes records into. Named to match the wrapper variable so the wrapper's terraform.tfvars supplies it directly. Grants the deployer Private DNS Zone Contributor on the zone."
  type        = string
  default     = null
}

variable "appconfig_private_dns_zone_id" {
  description = "OPTIONAL: Resource ID of the App Configuration privatelink DNS zone the wrapper writes records into. Named to match the wrapper variable so the wrapper's terraform.tfvars supplies it directly. Grants the deployer Private DNS Zone Contributor on the zone."
  type        = string
  default     = null
}

variable "state_storage_account_id" {
  description = "OPTIONAL: Resource ID of the storage account holding Terraform state (backend \"azurerm\" with use_azuread_auth). Grants the deployer Storage Blob Data Contributor on it."
  type        = string
  default     = null
}

variable "operator_principal_ids" {
  description = "OPTIONAL: Object IDs of additional people who operate and troubleshoot deployments (not the deployment principal). Each gets read-only access at the deployment resource group: Reader, App Configuration Data Reader (the provisioner's status keys), and Log Analytics Reader (the provisioner log). The identity running this Terraform is included automatically; see grant_executor_operator_access."
  type        = map(string)
  default     = {}
}

variable "grant_executor_operator_access" {
  description = "OPTIONAL: Give the identity running this Terraform the same read-only operator access as operator_principal_ids. Set false when this runs as a pipeline principal that should hold no standing grants."
  type        = bool
  default     = true
}

variable "include_soft_delete_purge" {
  description = "Include purge of soft-deleted Key Vaults and App Configuration stores in the subscription-scope grant. The provider purges these when recreating a deployment; omit to require manual purges instead."
  type        = bool
  default     = true
}

variable "name_suffix" {
  description = "OPTIONAL: Suffix making custom role names unique in the tenant. Defaults to resource_group_name."
  type        = string
  default     = null
}

variable "tags" {
  description = "OPTIONAL: Tags for the resource group and identities created here."
  type        = map(string)
  default     = {}
}
