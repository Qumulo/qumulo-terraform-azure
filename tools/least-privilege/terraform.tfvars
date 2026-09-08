# ************************* LEAST-PRIVILEGE SETUP VARIABLES ************************
# This configuration inherits the deployment's shared values from the wrapper's
# top-level terraform.tfvars, so subscription, subnet, resource group, location,
# tags, key vault, and DNS zones are specified once. Run it with both files, in
# this order (the later file wins, so values here override inherited ones):
#
#   terraform init
#   terraform apply -var-file=../../terraform.tfvars -var-file=terraform.tfvars
#
# Terraform warns about the wrapper file's variables this configuration does not
# declare ("Value for undeclared variable"); those warnings are expected and
# harmless.
#
# Inherited from ../../terraform.tfvars: azure_subscription_id, location,
# resource_group_name, subnet_id, tags, key_vault_id, admin_pwd_or_keyvault_secret_id,
# deletion_protection, persistent_storage_resource_group, custom_image_id,
# provisioner_custom_image_id, blob_/keyvault_/appconfig_private_dns_zone_id.
#
# This file holds only what the wrapper does not know:
# admin_password_key_vault_id     - (OPTIONAL) Resource ID of the vault holding the cluster admin password,
#                                    only when admin_pwd_or_keyvault_secret_id is a secret URI (the URI
#                                    does not name the vault's resource group). Default = null.
# deployer_principal_id           - (OPTIONAL) Object ID of an existing principal to deploy as (a user,
#                                    service principal, or runner-VM managed identity). Default = null:
#                                    a user-assigned managed identity named <rg>-deployer is created
#                                    instead -- attach it to the terraform runner VM (deployer_identity
#                                    output) and pin it with ARM_CLIENT_ID / AZURE_CLIENT_ID.
# deployer_principal_type         - (OPTIONAL) User, Group, or ServicePrincipal for deployer_principal_id.
#                                    Default = "User"; managed identities are ServicePrincipal.
# operator_principal_ids          - (OPTIONAL) Object IDs of additional humans who watch and troubleshoot
#                                    deployments; each gets read-only access (Reader, App Configuration
#                                    Data Reader, Log Analytics Reader) at the deployment resource group.
#                                    The identity running this terraform is included automatically.
# grant_executor_operator_access  - (OPTIONAL) Grant the identity running this terraform the operator
#                                    read-only access. Default = true; set false for pipeline principals.
# create_resource_group           - (OPTIONAL) Create the deployment resource group here. Default = true;
#                                    set false to reference one that already exists.
# state_storage_account_id        - (OPTIONAL) Storage account holding Terraform state when the wrapper
#                                    uses an AzureAD-authenticated azurerm backend; grants the deployer
#                                    Storage Blob Data Contributor on it.
# include_soft_delete_purge       - (OPTIONAL) Include soft-delete purge rights in the subscription-scope
#                                    grant. Default = true; set false to require manual purges.
# name_suffix                     - (OPTIONAL) Suffix keeping custom role names tenant-unique.
#                                    Default = resource_group_name.
#
# Finding an object ID with the az CLI:
#   az ad signed-in-user show --query id -o tsv                      (yourself)
#   az ad user show --id person@example.com --query id -o tsv        (another user)
#   az ad sp show --id <appId> --query id -o tsv                     (service principal)
#   az identity show -g <rg> -n <name> --query principalId -o tsv    (managed identity)

#------------OPTIONAL------------------
admin_password_key_vault_id    = null
deployer_principal_id          = null
deployer_principal_type        = "User"
operator_principal_ids         = {}
grant_executor_operator_access = true
create_resource_group          = true
state_storage_account_id       = null
include_soft_delete_purge      = true
name_suffix                    = null
