output "resource_group_name" {
  description = "Pass to the wrapper's resource_group_name."
  value       = var.resource_group_name
}

output "cluster_node_identity_id" {
  description = "Pass to the wrapper's cluster_node_identity_id."
  value       = azurerm_user_assigned_identity.cluster_node.id
}

output "provisioner_identity_id" {
  description = "Pass to the wrapper's provisioner_identity_id."
  value       = azurerm_user_assigned_identity.provisioner.id
}

output "deployer_identity" {
  description = "The created deployer identity (attach it to the terraform runner VM). Null when deployer_principal_id was supplied instead."
  value = var.deployer_principal_id == null ? {
    id           = azurerm_user_assigned_identity.deployer[0].id
    client_id    = azurerm_user_assigned_identity.deployer[0].client_id
    principal_id = azurerm_user_assigned_identity.deployer[0].principal_id
  } : null
}

output "deployer_role_definition_ids" {
  description = "The custom role definitions granted to the deployer principal."
  value = {
    resource_group     = azurerm_role_definition.deployer.role_definition_resource_id
    subscription       = azurerm_role_definition.deployer_subscription.role_definition_resource_id
    network            = azurerm_role_definition.deployer_network.role_definition_resource_id
    persistent_storage = var.persistent_storage_resource_group == null ? null : azurerm_role_definition.deployer_storage[0].role_definition_resource_id
  }
}

output "wrapper_tfvars" {
  description = "Values to set in the wrapper's terraform.tfvars for this deployment."
  value = merge(
    {
      resource_group_name = var.resource_group_name
      subnet_id           = var.subnet_id
    },
    {
      cluster_node_identity_id = azurerm_user_assigned_identity.cluster_node.id
      provisioner_identity_id  = azurerm_user_assigned_identity.provisioner.id
    },
    var.key_vault_id == null ? {} : { key_vault_id = var.key_vault_id },
    var.ssh_public_key_id == null ? {} : { ssh_public_key_id = var.ssh_public_key_id },
  )
}
