# =============================================================================
# BACKEND CONFIGURATION
# =============================================================================
# Azure Blob Storage Backend (Default)
# -----------------------------------------------------------------------------
# Comment out this entire block to use local backend instead
# Note: unlike the S3 backend, the azurerm backend has no workspace_key_prefix
# argument. When using Terraform workspaces, state blobs are automatically
# named "<key>env:<workspace>" within the same container.
terraform {
  backend "azurerm" {
    resource_group_name  = "my-tfstate-rg"
    storage_account_name = "mytfstatestorage"
    container_name       = "tf-state"
    key                  = "cnq/terraform.tfstate"
    use_azuread_auth     = true
  }
}
