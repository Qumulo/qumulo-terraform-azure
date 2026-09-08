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
# resource_group_name, subnet_id, tags, key_vault_id, deletion_protection,
# persistent_storage_resource_group, blob_/keyvault_/appconfig_private_dns_zone_id.
#
# This file holds only what the wrapper does not know:
# deployer_principal_id           - Object ID of the principal that runs terraform (a user, service
#                                    principal, or runner-VM managed identity). Exactly one of this or
#                                    create_deployer_identity.
# create_deployer_identity        - (OPTIONAL) Create a user-assigned managed identity for a runner VM
#                                    instead of granting an existing principal. Default = false.
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

#-----------REQUIRED-------------------
deployer_principal_id = "00000000-0000-0000-0000-000000000000"

#------------OPTIONAL------------------
create_deployer_identity       = false
deployer_principal_type       = "User"
operator_principal_ids        = {}
grant_executor_operator_access = true
create_resource_group         = true
state_storage_account_id      = null
include_soft_delete_purge     = true
name_suffix                   = null
