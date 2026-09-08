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

  persistent_storage_scope = var.persistent_storage_resource_group_name == null ? null : data.azurerm_resource_group.persistent_storage[0].id

  key_vault_scope = coalesce(var.key_vault_id, local.resource_group_id)

  deployer_principal_id   = var.create_deployer_identity ? azurerm_user_assigned_identity.deployer[0].principal_id : var.deployer_principal_id
  deployer_principal_type = var.create_deployer_identity ? "ServicePrincipal" : var.deployer_principal_type

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
  count = var.persistent_storage_resource_group_name == null ? 0 : 1

  name = var.persistent_storage_resource_group_name
}

#=======================================================================================
# Identities
#=======================================================================================

resource "azurerm_user_assigned_identity" "deployer" {
  count = var.create_deployer_identity ? 1 : 0

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
        "Microsoft.Storage/storageAccounts/listKeys/action",
        "Microsoft.Storage/storageAccounts/blobServices/containers/read",
        "Microsoft.Storage/storageAccounts/blobServices/containers/write",
        "Microsoft.Storage/storageAccounts/blobServices/containers/delete",

        "Microsoft.KeyVault/vaults/read",
        "Microsoft.KeyVault/vaults/write",
        "Microsoft.KeyVault/vaults/delete",
        "Microsoft.AppConfiguration/configurationStores/read",
        "Microsoft.AppConfiguration/configurationStores/write",
        "Microsoft.AppConfiguration/configurationStores/delete",
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
  count = var.persistent_storage_resource_group_name == null ? 0 : 1

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
        "Microsoft.Storage/storageAccounts/listKeys/action",
        "Microsoft.Storage/storageAccounts/blobServices/containers/read",
        "Microsoft.Storage/storageAccounts/blobServices/containers/write",
        "Microsoft.Storage/storageAccounts/blobServices/containers/delete",
        "Microsoft.KeyVault/vaults/read",
        "Microsoft.KeyVault/vaults/write",
        "Microsoft.KeyVault/vaults/delete",
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
  skip_service_principal_aad_check = var.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_persistent_storage" {
  count = var.persistent_storage_resource_group_name == null ? 0 : 1

  scope                            = local.persistent_storage_scope
  role_definition_id               = azurerm_role_definition.deployer_storage[0].role_definition_resource_id
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = var.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_subscription" {
  scope                            = local.subscription_scope
  role_definition_id               = azurerm_role_definition.deployer_subscription.role_definition_resource_id
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = var.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_network" {
  scope                            = local.vnet_id
  role_definition_id               = azurerm_role_definition.deployer_network.role_definition_resource_id
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = var.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_customer_key_vault" {
  count = var.key_vault_id == null ? 0 : 1

  scope                            = var.key_vault_id
  role_definition_name             = "Key Vault Administrator"
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = var.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_private_dns" {
  for_each = toset(var.private_dns_zone_ids)

  scope                            = each.value
  role_definition_name             = "Private DNS Zone Contributor"
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = var.create_deployer_identity
}

resource "azurerm_role_assignment" "deployer_state_storage" {
  count = var.state_storage_account_id == null ? 0 : 1

  scope                            = var.state_storage_account_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = local.deployer_principal_id
  principal_type                   = local.deployer_principal_type
  skip_service_principal_aad_check = var.create_deployer_identity
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
  scope                            = local.key_vault_scope
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_user_assigned_identity.cluster_node.principal_id
  skip_service_principal_aad_check = true
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
  scope                            = local.key_vault_scope
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_user_assigned_identity.provisioner.principal_id
  skip_service_principal_aad_check = true
}
