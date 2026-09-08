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
  description = "Object ID of the principal that runs terraform (a user, service principal, or the managed identity of a runner VM). Exactly one of this or create_deployer_identity must be set."
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

variable "create_deployer_identity" {
  description = "Create a user-assigned managed identity to run terraform from a runner VM, instead of granting an existing principal. Exactly one of this or deployer_principal_id must be set."
  type        = bool
  default     = false

  validation {
    condition     = var.create_deployer_identity != (var.deployer_principal_id != null)
    error_message = "Set exactly one of deployer_principal_id or create_deployer_identity."
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

variable "persistent_storage_resource_group_name" {
  description = "OPTIONAL: Resource group holding persistent storage accounts when it differs from resource_group_name (the wrapper's persistent_storage_resource_group). Must already exist. Deployer and node grants are extended to it."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "OPTIONAL: Resource IDs of privatelink DNS zones the deployer writes records into (the wrapper's private_link_*_dns_zone_id values). Grants Private DNS Zone Contributor on each."
  type        = list(string)
  default     = []
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
