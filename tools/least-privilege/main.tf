#Standalone least-privilege setup for CNQ Azure deployments. Run once as a privileged
#administrator; afterwards the deployment itself runs under the narrow grants created here.
#PERMISSIONS.md documents why every right below exists and walks through creating the same
#setup in the Azure Portal.

locals {
  suffix = coalesce(var.name_suffix, var.resource_group_name)

  subnet_id_parts = regex("^(?P<vnet_id>/subscriptions/(?P<subscription_id>[^/]+)/resourceGroups/(?P<resource_group>[^/]+)/providers/Microsoft.Network/virtualNetworks/[^/]+)/subnets/[^/]+$", var.subnet_id)
  vnet_id         = local.subnet_id_parts.vnet_id

  subscription_scope = "/subscriptions/${var.azure_subscription_id}"

  resource_group_id = var.create_resource_group ? azurerm_resource_group.deployment[0].id : data.azurerm_resource_group.deployment[0].id

  persistent_storage_scope = var.persistent_storage_resource_group == null ? null : data.azurerm_resource_group.persistent_storage[0].id

  key_vault_scope = coalesce(var.key_vault_id, local.resource_group_id)

  #A vault is granted by role assignments when it uses the RBAC permission model and by
  #access policies otherwise. The provider's own vault is always RBAC.
  key_vault_id_pattern = "^/subscriptions/[^/]+/resourceGroups/(?P<resource_group>[^/]+)/providers/Microsoft\\.KeyVault/vaults/(?P<name>[^/]+)$"

  customer_key_vault_parts = var.key_vault_id == null ? null : regex(local.key_vault_id_pattern, var.key_vault_id)
  customer_key_vault_rbac  = var.key_vault_id == null ? true : data.azurerm_key_vault.customer[0].rbac_authorization_enabled

  #The admin password reference is sensitive as a whole (it may be the password itself); only a
  #Key Vault secret resource ID is extracted from it, and that is not secret.
  admin_secret_id = var.admin_pwd_or_keyvault_secret_id == null ? null : nonsensitive(try(
    regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+/secrets/[^/]+$", var.admin_pwd_or_keyvault_secret_id),
    null,
  ))
  admin_password_vault_id    = var.admin_password_key_vault_id != null ? var.admin_password_key_vault_id : (local.admin_secret_id == null ? null : regex("^(.*)/secrets/[^/]+$", local.admin_secret_id)[0])
  admin_password_vault_parts = local.admin_password_vault_id == null ? null : regex(local.key_vault_id_pattern, local.admin_password_vault_id)
  admin_password_vault_rbac  = local.admin_password_vault_id == null ? true : data.azurerm_key_vault.admin_password[0].rbac_authorization_enabled
  #The read grant lands on the secret itself when the reference names it, else on the vault.
  admin_password_read_scope = local.admin_password_vault_id == null ? null : coalesce(local.admin_secret_id, local.admin_password_vault_id)

  #A gallery image is granted at its gallery, so a new image definition or version needs no new grant.
  image_scopes = toset([
    for id in compact([var.custom_image_id, var.provisioner_custom_image_id]) :
    can(regex("/galleries/[^/]+/images/", id)) ? regex("^(.*/galleries/[^/]+)/images/", id)[0] : id
  ])

  #The deployer defaults to a created identity; supplying deployer_principal_id overrides.
  create_deployer_identity = var.deployer_principal_id == null

  deployer_principal_id   = local.create_deployer_identity ? azurerm_user_assigned_identity.deployer[0].principal_id : var.deployer_principal_id
  deployer_principal_type = local.create_deployer_identity ? "ServicePrincipal" : var.deployer_principal_type

  operator_ids = toset(concat(
    var.grant_executor_operator_access ? [data.azurerm_client_config.current.object_id] : [],
    values(var.operator_principal_ids),
  ))
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "deployment" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

data "azurerm_resource_group" "deployment" {
  count = var.create_resource_group ? 0 : 1

  name = var.resource_group_name
}

data "azurerm_resource_group" "persistent_storage" {
  count = var.persistent_storage_resource_group == null ? 0 : 1

  name = var.persistent_storage_resource_group
}

#=======================================================================================
# Identities
#=======================================================================================

resource "azurerm_user_assigned_identity" "deployer" {
  count = local.create_deployer_identity ? 1 : 0

  name                = "${var.resource_group_name}-deployer"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  depends_on = [azurerm_resource_group.deployment]
}

resource "azurerm_user_assigned_identity" "cluster_node" {
  name                = "${var.resource_group_name}-node"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  depends_on = [azurerm_resource_group.deployment]
}

resource "azurerm_user_assigned_identity" "provisioner" {
  name                = "${var.resource_group_name}-provisioner"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  depends_on = [azurerm_resource_group.deployment]
}

#=======================================================================================
# Custom role: deployer, resource-group scope
#=======================================================================================

resource "azurerm_role_definition" "deployer" {
  name        = "Qumulo CNQ Deployer (${local.suffix})"
  scope       = local.resource_group_id
  description = "Minimum resource-group permissions to deploy and operate a CNQ cluster with the qumulo terraform provider and wrapper."

  assignable_scopes = [local.resource_group_id]

  permissions {
    actions = concat(
      [
        "Microsoft.Resources/subscriptions/resourceGroups/read",
        "Microsoft.Resources/subscriptions/resourceGroups/write",

        "Microsoft.Compute/virtualMachines/read",
        "Microsoft.Compute/virtualMachines/write",
        "Microsoft.Compute/virtualMachines/delete",
        "Microsoft.Compute/virtualMachines/extensions/write",
        "Microsoft.Compute/disks/read",
        "Microsoft.Compute/disks/write",
        "Microsoft.Compute/disks/delete",

        "Microsoft.Network/networkInterfaces/read",
        "Microsoft.Network/networkInterfaces/write",
        "Microsoft.Network/networkInterfaces/delete",
        "Microsoft.Network/networkInterfaces/join/action",
        "Microsoft.Network/networkSecurityGroups/read",
        "Microsoft.Network/networkSecurityGroups/write",
        "Microsoft.Network/networkSecurityGroups/delete",
        "Microsoft.Network/networkSecurityGroups/join/action",
        "Microsoft.Network/applicationSecurityGroups/read",
        "Microsoft.Network/applicationSecurityGroups/write",
        "Microsoft.Network/applicationSecurityGroups/delete",
        "Microsoft.Network/applicationSecurityGroups/joinIpConfiguration/action",
        "Microsoft.Network/publicIPAddresses/read",
        "Microsoft.Network/publicIPAddresses/write",
        "Microsoft.Network/publicIPAddresses/delete",
        "Microsoft.Network/publicIPAddresses/join/action",

        "Microsoft.Network/privateEndpoints/read",
        "Microsoft.Network/privateEndpoints/write",
        "Microsoft.Network/privateEndpoints/delete",
        "Microsoft.Network/privateEndpoints/privateDnsZoneGroups/read",
        "Microsoft.Network/privateEndpoints/privateDnsZoneGroups/write",
        "Microsoft.Network/privateEndpoints/privateDnsZoneGroups/delete",

        "Microsoft.Storage/storageAccounts/read",
        "Microsoft.Storage/storageAccounts/write",
        "Microsoft.Storage/storageAccounts/delete",
        "Microsoft.Storage/storageAccounts/PrivateEndpointConnectionsApproval/action",
        "Microsoft.Storage/storageAccounts/listKeys/action",
        "Microsoft.Storage/storageAccounts/blobServices/containers/read",
        "Microsoft.Storage/storageAccounts/blobServices/containers/write",
        "Microsoft.Storage/storageAccounts/blobServices/containers/delete",

        "Microsoft.KeyVault/vaults/read",
        "Microsoft.KeyVault/vaults/write",
        "Microsoft.KeyVault/vaults/delete",
        "Microsoft.KeyVault/vaults/PrivateEndpointConnectionsApproval/action",
        "Microsoft.AppConfiguration/configurationStores/read",
        "Microsoft.AppConfiguration/configurationStores/write",
        "Microsoft.AppConfiguration/configurationStores/delete",
        "Microsoft.AppConfiguration/configurationStores/PrivateEndpointConnectionsApproval/action",
        "Microsoft.AppConfiguration/configurationStores/keyValues/action",
        "Microsoft.AppConfiguration/configurationStores/keyValues/write",
        "Microsoft.AppConfiguration/configurationStores/keyValues/delete",

        "Microsoft.ManagedIdentity/userAssignedIdentities/read",
        "Microsoft.ManagedIdentity/userAssignedIdentities/write",
        "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",

        "Microsoft.Authorization/roleAssignments/read",
        "Microsoft.Authorization/roleAssignments/write",
        "Microsoft.Authorization/roleAssignments/delete",
        "Microsoft.Authorization/permissions/read",

        "Microsoft.OperationalInsights/workspaces/read",
        "Microsoft.OperationalInsights/workspaces/write",
        "Microsoft.OperationalInsights/workspaces/delete",
        "Microsoft.OperationalInsights/workspaces/tables/read",
        "Microsoft.OperationalInsights/workspaces/tables/write",
        "Microsoft.OperationalInsights/workspaces/sharedKeys/action",
        "Microsoft.Insights/DataCollectionEndpoints/Read",
        "Microsoft.Insights/DataCollectionEndpoints/Write",
        "Microsoft.Insights/DataCollectionEndpoints/Delete",
        "Microsoft.Insights/DataCollectionRules/Read",
        "Microsoft.Insights/DataCollectionRules/Write",
        "Microsoft.Insights/DataCollectionRules/Delete",
        "Microsoft.Insights/DataCollectionRuleAssociations/Read",
        "Microsoft.Insights/DataCollectionRuleAssociations/Write",
        "Microsoft.Insights/DataCollectionRuleAssociations/Delete",
      ],
      var.deletion_protection ? [
        "Microsoft.Authorization/locks/read",
        "Microsoft.Authorization/locks/write",
        "Microsoft.Authorization/locks/delete",
      ] : [],
    )

    data_actions = [
      "Microsoft.KeyVault/vaults/secrets/getSecret/action",
      "Microsoft.KeyVault/vaults/secrets/setSecret/action",
      "Microsoft.KeyVault/vaults/secrets/readMetadata/action",
      "Microsoft.KeyVault/vaults/storageaccounts/read",
      "Microsoft.KeyVault/vaults/storageaccounts/set/action",
      "Microsoft.KeyVault/vaults/storageaccounts/delete",
      "Microsoft.KeyVault/vaults/storageaccounts/sas/read",
      "Microsoft.KeyVault/vaults/storageaccounts/sas/set/action",
      "Microsoft.KeyVault/vaults/storageaccounts/sas/delete",
    ]
  }
}

#=======================================================================================
# Custom role: deployer, subscription scope
#=======================================================================================

resource "azurerm_role_definition" "deployer_subscription" {
  name        = "Qumulo CNQ Deployer Subscription (${local.suffix})"
  scope       = local.subscription_scope
  description = "Subscription-level permissions for CNQ deployment: reads that have no resource-group scope, and soft-delete purges."

  assignable_scopes = [local.subscription_scope]

  permissions {
    actions = concat(
      [
        "Microsoft.Resources/subscriptions/read",
        "Microsoft.Resources/subscriptions/resources/read",
        "Microsoft.Compute/skus/read",
      ],
      var.include_soft_delete_purge ? [
        "Microsoft.KeyVault/deletedVaults/read",
        "Microsoft.KeyVault/locations/deletedVaults/read",
        "Microsoft.KeyVault/locations/deletedVaults/purge/action",
        "Microsoft.AppConfiguration/locations/deletedConfigurationStores/read",
        "Microsoft.AppConfiguration/locations/deletedConfigurationStores/purge/action",
      ] : [],
    )
  }
}

#=======================================================================================
# Custom roles: network, virtual-network scope
#=======================================================================================

resource "azurerm_role_definition" "deployer_network" {
  name        = "Qumulo CNQ Deployer Network (${local.suffix})"
  scope       = local.vnet_id
  description = "Read and join the CNQ cluster's subnet, and link private DNS zones to its virtual network."

  assignable_scopes = [local.vnet_id]

  permissions {
    actions = [
      "Microsoft.Network/virtualNetworks/join/action",
      "Microsoft.Network/virtualNetworks/subnets/read",
      "Microsoft.Network/virtualNetworks/subnets/join/action",
      "Microsoft.Network/virtualNetworks/checkIpAddressAvailability/read",
    ]
  }
}

resource "azurerm_role_definition" "subnet_join" {
  name        = "Qumulo CNQ Subnet Join (${local.suffix})"
  scope       = local.vnet_id
  description = "Join the CNQ cluster's subnet."

  assignable_scopes = [local.vnet_id]

  permissions {
    actions = [
      "Microsoft.Network/virtualNetworks/subnets/join/action",
    ]
  }
}

#=======================================================================================
# Custom role: deployer storage, persistent-storage resource-group scope
#=======================================================================================

resource "azurerm_role_definition" "deployer_storage" {
  count = var.persistent_storage_resource_group == null ? 0 : 1

  name        = "Qumulo CNQ Deployer Storage (${local.suffix})"
  scope       = local.persistent_storage_scope
  description = "Minimum permissions on the persistent-storage resource group: storage accounts, the Key Vault, and their locks."

  assignable_scopes = [local.persistent_storage_scope]

  permissions {
    actions = concat(
      [
        "Microsoft.Resources/subscriptions/resourceGroups/read",
        "Microsoft.Storage/storageAccounts/read",
        "Microsoft.Storage/storageAccounts/write",
        "Microsoft.Storage/storageAccounts/delete",
        "Microsoft.Storage/storageAccounts/PrivateEndpointConnectionsApproval/action",
        "Microsoft.Storage/storageAccounts/listKeys/action",
        "Microsoft.Storage/storageAccounts/blobServices/containers/read",
        "Microsoft.Storage/storageAccounts/blobServices/containers/write",
        "Microsoft.Storage/storageAccounts/blobServices/containers/delete",
        "Microsoft.KeyVault/vaults/read",
        "Microsoft.KeyVault/vaults/write",
        "Microsoft.KeyVault/vaults/delete",
        "Microsoft.KeyVault/vaults/PrivateEndpointConnectionsApproval/action",
      ],
      var.deletion_protection ? [
        "Microsoft.Authorization/locks/read",
        "Microsoft.Authorization/locks/write",
        "Microsoft.Authorization/locks/delete",
      ] : [],
    )

    data_actions = [
      "Microsoft.KeyVault/vaults/secrets/getSecret/action",
      "Microsoft.KeyVault/vaults/secrets/setSecret/action",
      "Microsoft.KeyVault/vaults/secrets/readMetadata/action",
      "Microsoft.KeyVault/vaults/storageaccounts/read",
      "Microsoft.KeyVault/vaults/storageaccounts/set/action",
      "Microsoft.KeyVault/vaults/storageaccounts/delete",
      "Microsoft.KeyVault/vaults/storageaccounts/sas/read",
      "Microsoft.KeyVault/vaults/storageaccounts/sas/set/action",
      "Microsoft.KeyVault/vaults/storageaccounts/sas/delete",
    ]
  }
}

#=======================================================================================
# Custom role: cluster node, resource-group scope
#=======================================================================================

resource "azurerm_role_definition" "cluster_node" {
  name        = "Qumulo CNQ Cluster Node (${local.suffix})"
  scope       = local.resource_group_id
  description = "Minimum permissions for Qumulo Core's floating-IP management on cluster node NICs."

  assignable_scopes = [local.resource_group_id]

  permissions {
    actions = [
      "Microsoft.Network/networkInterfaces/read",
      "Microsoft.Network/networkInterfaces/write",
      "Microsoft.Network/applicationSecurityGroups/joinIpConfiguration/action",
      "Microsoft.Network/networkSecurityGroups/join/action",
    ]
  }
}

#=======================================================================================
# Deployer role assignments
#=======================================================================================

resource "azurerm_role_assignment" "deployer_resource_group" {
  scope                            = local.resource_group_id
  role_definition_id               = azurerm_role_definition.deployer.role_definition_resource_id
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = local.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_persistent_storage" {
  count = var.persistent_storage_resource_group == null ? 0 : 1

  scope                            = local.persistent_storage_scope
  role_definition_id               = azurerm_role_definition.deployer_storage[0].role_definition_resource_id
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = local.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_subscription" {
  scope                            = local.subscription_scope
  role_definition_id               = azurerm_role_definition.deployer_subscription.role_definition_resource_id
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = local.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_network" {
  scope                            = local.vnet_id
  role_definition_id               = azurerm_role_definition.deployer_network.role_definition_resource_id
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = local.create_deployer_identity
}

data "azurerm_key_vault" "customer" {
  count = var.key_vault_id == null ? 0 : 1

  name                = local.customer_key_vault_parts.name
  resource_group_name = local.customer_key_vault_parts.resource_group
}

resource "azurerm_role_assignment" "deployer_customer_key_vault" {
  count = var.key_vault_id != null && local.customer_key_vault_rbac ? 1 : 0

  scope                            = var.key_vault_id
  role_definition_name             = "Key Vault Administrator"
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = local.create_deployer_identity
}

#Access-policy vault: the management-plane read the provider needs comes from Reader, the
#data plane from the policy below.
resource "azurerm_role_assignment" "deployer_customer_key_vault_reader" {
  count = var.key_vault_id != null && !local.customer_key_vault_rbac ? 1 : 0

  scope                            = var.key_vault_id
  role_definition_name             = "Reader"
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = local.create_deployer_identity
}

resource "azurerm_key_vault_access_policy" "deployer_customer_key_vault" {
  count = var.key_vault_id != null && !local.customer_key_vault_rbac ? 1 : 0

  key_vault_id = var.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = local.deployer_principal_id

  secret_permissions  = ["Get", "List", "Set", "Delete"]
  storage_permissions = ["Get", "List", "Set", "Delete", "GetSAS", "ListSAS", "SetSAS", "DeleteSAS"]
}

data "azurerm_key_vault" "admin_password" {
  count = local.admin_password_vault_id == null ? 0 : 1

  name                = local.admin_password_vault_parts.name
  resource_group_name = local.admin_password_vault_parts.resource_group
}

resource "azurerm_role_assignment" "deployer_admin_password_secret" {
  count = local.admin_password_vault_id != null && local.admin_password_vault_rbac ? 1 : 0

  scope                            = local.admin_password_read_scope
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = local.create_deployer_identity
}

resource "azurerm_key_vault_access_policy" "deployer_admin_password_secret" {
  count = local.admin_password_vault_id != null && !local.admin_password_vault_rbac ? 1 : 0

  key_vault_id = local.admin_password_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = local.deployer_principal_id

  secret_permissions = ["Get"]
}

resource "azurerm_role_assignment" "deployer_image_reader" {
  for_each = local.image_scopes

  scope                            = each.value
  role_definition_name             = "Reader"
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = local.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_private_dns" {
  for_each = toset(compact([var.blob_private_dns_zone_id, var.keyvault_private_dns_zone_id, var.appconfig_private_dns_zone_id]))

  scope                            = each.value
  role_definition_name             = "Private DNS Zone Contributor"
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = local.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_state_storage" {
  count = var.state_storage_account_id == null ? 0 : 1

  scope                            = var.state_storage_account_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = local.create_deployer_identity
}

#=======================================================================================
# Operator (human) read-only assignments
#=======================================================================================

resource "azurerm_role_assignment" "operator_reader" {
  for_each = local.operator_ids

  scope                = local.resource_group_id
  role_definition_name = "Reader"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "operator_appconfig_data_reader" {
  for_each = local.operator_ids

  scope                = local.resource_group_id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "operator_log_reader" {
  for_each = local.operator_ids

  scope                = local.resource_group_id
  role_definition_name = "Log Analytics Reader"
  principal_id         = each.value
}

#=======================================================================================
# Cluster node identity role assignments
#=======================================================================================

resource "azurerm_role_assignment" "node_nics" {
  scope                            = local.resource_group_id
  role_definition_id               = azurerm_role_definition.cluster_node.role_definition_resource_id
  principal_id                     = azurerm_user_assigned_identity.cluster_node.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "node_subnet_join" {
  scope                            = local.vnet_id
  role_definition_id               = azurerm_role_definition.subnet_join.role_definition_resource_id
  principal_id                     = azurerm_user_assigned_identity.cluster_node.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "node_key_vault_secrets" {
  count = local.customer_key_vault_rbac ? 1 : 0

  scope                            = local.key_vault_scope
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_user_assigned_identity.cluster_node.principal_id
  skip_service_principal_aad_check = true
}

moved {
  from = azurerm_role_assignment.node_key_vault_secrets
  to   = azurerm_role_assignment.node_key_vault_secrets[0]
}

moved {
  from = azurerm_role_assignment.provisioner_key_vault_secrets
  to   = azurerm_role_assignment.provisioner_key_vault_secrets[0]
}

resource "azurerm_key_vault_access_policy" "node_key_vault_secrets" {
  count = local.customer_key_vault_rbac ? 0 : 1

  key_vault_id = var.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.cluster_node.principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_role_assignment" "node_blob_reader" {
  scope                            = coalesce(local.persistent_storage_scope, local.resource_group_id)
  role_definition_name             = "Storage Blob Data Reader"
  principal_id                     = azurerm_user_assigned_identity.cluster_node.principal_id
  skip_service_principal_aad_check = true
}

#=======================================================================================
# Provisioner identity role assignments
#=======================================================================================

resource "azurerm_role_assignment" "provisioner_appconfig_data_owner" {
  scope                            = local.resource_group_id
  role_definition_name             = "App Configuration Data Owner"
  principal_id                     = azurerm_user_assigned_identity.provisioner.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "provisioner_reader" {
  scope                            = local.resource_group_id
  role_definition_name             = "Reader"
  principal_id                     = azurerm_user_assigned_identity.provisioner.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "provisioner_key_vault_secrets" {
  count = local.customer_key_vault_rbac ? 1 : 0

  scope                            = local.key_vault_scope
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_user_assigned_identity.provisioner.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_key_vault_access_policy" "provisioner_key_vault_secrets" {
  count = local.customer_key_vault_rbac ? 0 : 1

  key_vault_id = var.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.provisioner.principal_id

  secret_permissions = ["Get", "List"]
}
