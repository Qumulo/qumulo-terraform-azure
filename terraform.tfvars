# ****************************** QUMULO PROVIDER VARIABLES ********************
# *********** Azure Variables ***********
# deployment_name               - A name for this deployment, lowercase letters, digits, and interior hyphens, 2-15 characters.
# location                      - Azure region for deployment.
# resource_group_name           - Azure resource group name. Created by the provider if it does not already exist.
# subnet_id                     - Full Azure resource ID of the pre-configured subnet for cluster nodes. Must have the Microsoft.KeyVault and Microsoft.Storage service endpoints enabled.
# vm_type                       - Azure VM size for cluster nodes. Only L-series storage-optimized VMs are supported (e.g. Standard_L8s_v4).
# allow_cidrs                   - (OPTIONAL) CIDR blocks allowed to access the cluster (the subnet's address prefixes are used by default). Production clusters should restrict to known client/management networks. ie: 10.0.1.0/24
# availability_zones            - (OPTIONAL) Availability zones for deployment, e.g. ["1", "2", "3"]. Omit for zoneless regions.
# azure_environment             - (OPTIONAL) Azure cloud environment for the qumulo provider. "public" or "usgovernment". Default = "public".
# azure_subscription_id         - (OPTIONAL) Azure subscription ID. If omitted, resolved from ARM_SUBSCRIPTION_ID or the active Azure CLI context.
# cluster_node_identity_id      - (OPTIONAL) Resource ID of a user-assigned managed identity for cluster nodes. If omitted, the provider creates one.
# custom_image_id               - (OPTIONAL) Custom VM image resource ID for cluster nodes. If omitted, the default Qumulo image (Ubuntu) is used.
# key_vault_id                  - (OPTIONAL) Full Azure resource ID of a customer-managed Key Vault. If omitted, the provider creates one.
# provisioner_custom_image_id   - (OPTIONAL) Custom VM image resource ID for the provisioner instance. Defaults to the default Qumulo image.
# provisioner_identity_id       - (OPTIONAL) Resource ID of a user-assigned managed identity for the provisioner VM. If omitted, the provider creates one.
# provisioner_vm_type           - (OPTIONAL) Azure VM size for the provisioner instance (used during deploy operations). Defaults to the provider's built-in default.
# ssh_public_key_path           - (OPTIONAL) Path to a local SSH public key file for SSH access to cluster nodes. ie: "~/.ssh/id_rsa.pub"
# tags                          - (OPTIONAL) Tags to apply to all Azure resources created for this cluster.
#subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"

#-----------REQUIRED-------------------
deployment_name     = "my-deployment"
location            = "eastus2"
resource_group_name = "rg-qumulo"
subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
vm_type             = "Standard_L8s_v4"

#------------OPTIONAL------------------
allow_cidrs                 = null
availability_zones          = ["1", "2", "3"]
azure_environment           = "public"
azure_subscription_id       = null
cluster_node_identity_id    = null
custom_image_id             = null
key_vault_id                = null
provisioner_custom_image_id = null
provisioner_identity_id     = null
provisioner_vm_type         = null
ssh_public_key_path         = null
tags = {
  owner      = "smith"
  department = "it"
  purpose    = "prod"
}

# ***** Qumulo Cluster Variables ******
# admin_pwd_or_keyvault_secret_id - The password may be provided as text OR pulled from Azure Key Vault by referencing the secret's resource ID.  Admin password requirements:
#                                    8-128 characters long containing at least 3 of: lowercase letter, uppercase letter, number, special character. Sensitive -- not stored in Terraform state.
# cluster_product_type           - Cluster storage product type (immutable after creation). HOT: Optimized for frequently accessed data. COLD: Optimized for archival/infrequently accessed data.
# cluster_name                   - Name of the Qumulo cluster (2-15 characters, case preserved). Dash (-) is allowed if not the first or last character.
# node_count                     - Number of nodes in the cluster. Valid values: 1 (single node), or 3-24. 2 is not supported, 4 requires a single availability zone.
# deletion_protection            - Protects the cluster's VMs and storage accounts from deletion with CanNotDelete management locks. Default = true. Set to false to destroy.
# cluster_version                - (OPTIONAL) Qumulo software version. Defaults to latest. Immutable after creation. Upgrade version via cluster UI/API.
# floating_ips                   - (OPTIONAL) Floating IP addresses to assign to the cluster for client access. Must be free addresses within the subnet range.
# nexus_registration_key         - (OPTIONAL, Deprecated) Qumulo Nexus registration key for remote support. Obtain from https://nexus.qumulo.com/user/registration-key
# provider_timeout_minutes       - (OPTIONAL) The total time, in minutes, after which Terraform will abandon the provider deployment of the Qumulo cluster and timeout. Default is 30 minutes.
# storage_class                  - (OPTIONAL) HOT cluster default is INTELLIGENT_TIERING, or override to STANDARD.
# storage_replication_type       - (OPTIONAL) Azure storage replication type (immutable after creation). LRS or ZRS.
# soft_capacity_limit_tb         - (OPTIONAL) Soft capacity limit in TB (50 to 10000). Default is 500TB. Can be increased to add storage, but cannot be decreased.  It's like a quota, unused capacity is not billed.

#-----------REQUIRED-------------------
admin_pwd_or_keyvault_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault_name>/secrets/<secret_name>"
cluster_name                    = "CNQ-HOT"
cluster_product_type            = "HOT"
node_count                      = 3
deletion_protection             = true

#------------OPTIONAL------------------
cluster_version          = null
floating_ips             = null
nexus_registration_key   = null
provider_timeout_minutes = 30
storage_class            = null
storage_replication_type = null
soft_capacity_limit_tb   = 100

# ***** Miscellaneous Variables *******
# If boot behavior needs to be completely overridden contact support@qumulo.com.  Typically most needs can be accomodated with these pre/post hooks.
# node_hooks        - OPTIONAL: Advanced use only.  Hooks run pre-boot-network or post-qumulo-core-install. Executed only on first boot cycle.  See the docs.
# provisioner_hooks - OPTIONAL: Advanced use only.  Hooks run pre-deploy or post-cluster-formation on the provisioner.  Executed on every boot cycle.  See the docs.
node_hooks = {
  pre_run  = null
  post_run = null
}

provisioner_hooks = {
  pre_run  = null
  post_run = null
}

# ****************************** OPTIONAL ADVANCED SETTINGS *****************************
# disable_appconfig_public_network_access - (OPTIONAL) Disable public network access to the App Configuration instance the provider creates.
# disable_keyvault_public_network_access  - (OPTIONAL) Disable public network access to the Key Vault the provider creates or uses.
# networking_mode                         - (OPTIONAL) Network management mode for cluster nodes ("host_managed" default or "qumulo_managed").
# nsg_allow_ingress_icmp                  - (OPTIONAL) Enable ICMP ingress in the NSG rules the provider creates, for network diagnostics.
# persistent_storage_resource_group       - (OPTIONAL) Resource group containing persistent storage accounts and Key Vault, if different from resource_group_name.
# private_link_appconfig_dns_zone_id      - (OPTIONAL) Resource ID of the privatelink.azconfig.io private DNS zone.
# private_link_keyvault_dns_zone_id       - (OPTIONAL) Resource ID of the privatelink.vaultcore.azure.net private DNS zone.
# marketplace_image / provisioner_marketplace_image - (OPTIONAL) Azure Marketplace image specs; see aws-custom-images.md equivalent guidance in the provider docs.
# naming                                  - (OPTIONAL) Custom naming templates for Azure resources.
disable_appconfig_public_network_access = false
disable_keyvault_public_network_access  = false
networking_mode                         = null
nsg_allow_ingress_icmp                  = false
persistent_storage_resource_group       = null
private_link_appconfig_dns_zone_id      = null
private_link_keyvault_dns_zone_id       = null
marketplace_image                       = null
provisioner_marketplace_image           = null
naming                                  = null

# ***** OPTIONAL Cluster DNS *****
# cluster_fqdn - For clusters that want Qumulo Core to answer DNS queries directly with floating IPs (no separate DNS forwarder needed, unlike the AWS Route 53 Resolver pattern).
#                This may be left 'null' to bypass any FQDN DNS resolution on the Qumulo cluster.
cluster_fqdn = null
