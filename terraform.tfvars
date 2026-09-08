# ****************************** QUMULO PROVIDER VARIABLES ********************
# *********** Azure Variables ***********
# deployment_name               - A name for this deployment, lowercase letters, digits, and interior hyphens, 2-15 characters.
# location                      - Azure region for deployment.
# resource_group_name           - Seed name for this deployment's Azure resource group -- NOT the literal name. An immutable random suffix is always
#                                  appended (e.g. "rg-qumulo-h12g9v-rg") so every deployment gets its own dedicated resource group. WARNING: never
#                                  point two Qumulo clusters (or any other VM) at the same resource group -- Azure floating IPs are attached as
#                                  secondary IP configurations on node NICs, and the floating-IP reconciler strips secondary IPs from any NIC in the
#                                  resource group it doesn't recognize as its own, with no cluster filter. Sharing a resource group causes clusters to
#                                  fight over floating IPs indefinitely -- this has been observed firsthand as one cluster stealing another's IPs on boot.
# subnet_id                     - Full Azure resource ID of the pre-configured subnet for cluster nodes. Must have the Microsoft.KeyVault and Microsoft.Storage service endpoints enabled.
# vm_type                       - Azure VM size for cluster nodes. Only L-series storage-optimized VMs are supported (e.g. Standard_L8s_v4).
# azure_subscription_id         - Azure subscription ID. The qumulo provider only falls back to the ARM_SUBSCRIPTION_ID environment variable, not the
#                                  active Azure CLI context, so `az login` alone is not enough -- set this explicitly.
# allow_cidrs                   - (OPTIONAL) CIDR blocks allowed to access the cluster (the subnet's address prefixes are used by default). Production clusters should restrict to known client/management networks. ie: 10.0.1.0/24
# availability_zones            - (OPTIONAL) Availability zones for deployment, e.g. ["1", "2", "3"]. Omit for zoneless regions.
# azure_environment             - (OPTIONAL) Azure cloud environment for the qumulo provider. "public" or "usgovernment". Default = "public".
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
deployment_name       = "my-deployment"
location              = "eastus2"
resource_group_name   = "rg-qumulo"
subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
vm_type               = "Standard_L8s_v4"
azure_subscription_id = "00000000-0000-0000-0000-000000000000"

#------------OPTIONAL------------------
allow_cidrs                 = null
availability_zones          = ["1", "2", "3"]
azure_environment           = "public"
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
# admin_pwd_or_keyvault_secret_id - The password may be provided as text OR pulled from Azure Key Vault by referencing the secret's resource ID
#                                    (/subscriptions/.../vaults/<vault>/secrets/<secret>) or its secret URI (https://<vault>.vault.azure.net/secrets/<secret>/<version>).
#                                    Admin password requirements: 8-72 characters long containing at least 3 of: lowercase letter, uppercase letter, number, special character. Sensitive -- not stored in Terraform state.
#                                    If you use the URI form, the trailing /<version> segment is accepted (so a URI copied straight from the Portal parses fine) but is IGNORED --
#                                    Terraform always pulls the CURRENT/LATEST version of that Key Vault secret, even if the version you pasted is an older one.
#                                    This value is write-only, so Terraform never stores it in state -- but its current value is resupplied to the provider on every apply
#                                    that touches this resource (not just creation), since node/vm_type changes must authenticate to the existing cluster with it. It does
#                                    NOT itself rotate an already-running cluster's password though. To change the admin password after creation, use the Qumulo UI or
#                                    qumulo-cli directly on the cluster, and update the Key Vault secret to match (or vice versa) any time you do.
#                                    WARNING: there is no pre-flight check that this value matches an EXISTING cluster's actual password. If it has drifted out of
#                                    sync, applying a change that needs to authenticate to the cluster (scaling, vm_type changes, etc.) can fail partway through
#                                    with no automatic cleanup. Verify the two match before applying changes to an existing cluster.
# cluster_product_type           - Cluster storage product type (immutable after creation). HOT: Optimized for frequently accessed data. COLD: Optimized for archival/infrequently accessed data.
# cluster_name                   - Name of the Qumulo cluster (2-15 characters, case preserved). Dash (-) is allowed if not the first or last character.
# node_count                     - Number of nodes in the cluster. Valid values: 1 (single node), or 3-24. 2 is not supported, 4 requires a single availability zone.
# deletion_protection            - Protects the cluster's VMs and storage accounts from deletion with CanNotDelete management locks. Default = true. Set to false to destroy.
# cluster_uuid                   - (OPTIONAL) UUID of an existing cluster to import/adopt. Leave null for new deployments.
# cluster_version                - (OPTIONAL) Qumulo software version. Defaults to latest. Immutable after creation. Upgrade version via cluster UI/API.
# floating_ip_count              - (OPTIONAL) Number of floating IPs to assign to the cluster. Must be 0, or between 3 and 100. Requires networking_mode "host_managed". Default=3.
# nexus_registration_key         - (OPTIONAL, Deprecated) Qumulo Nexus registration key for remote support. Obtain from https://nexus.qumulo.com/user/registration-key. Ignored if nexus_api_token is set (see OPTIONAL ADVANCED SETTINGS below).
# provider_timeout_minutes       - (OPTIONAL) The default timeout, in minutes, applied to any of create/update/delete not overridden individually below. Default is 30 minutes.
# provider_create_timeout_minutes - (OPTIONAL) Timeout override for cluster creation, in minutes. Defaults to provider_timeout_minutes if unset. Consider raising this for larger node_count deployments.
# provider_update_timeout_minutes - (OPTIONAL) Timeout override for cluster updates (scaling, vm_type changes), in minutes. Defaults to provider_timeout_minutes if unset.
# provider_delete_timeout_minutes - (OPTIONAL) Timeout override for cluster deletion, in minutes. Defaults to provider_timeout_minutes if unset.
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
cluster_uuid                    = null
cluster_version                 = null
floating_ip_count               = 3
nexus_registration_key          = null
provider_timeout_minutes        = 30
provider_create_timeout_minutes = null
provider_update_timeout_minutes = null
provider_delete_timeout_minutes = null
storage_class                   = null
storage_replication_type        = null
soft_capacity_limit_tb          = 100

# ***** Miscellaneous Variables *******
# If boot behavior needs to be completely overridden contact support@qumulo.com or your Qumulo SE/SA.  Typically most needs can be accomodated with these pre/post hooks.  Hooks look in the hooks/ directory for the file.
# node_hooks_files        - OPTIONAL: Advanced use only.  Hooks run pre-boot-network or post-qumulo-core-install. override_file completely replaces the boot script. Executed only on first boot cycle.  See the docs.
#                           pre_run_files/post_run_files (lists) chain several hooks in order; see hooks/readme.md.
# provisioner_hooks_files - OPTIONAL: Advanced use only.  Hooks run pre-deploy or post-cluster-formation on the provisioner.  override_file completely replaces the boot script. Executed on every boot cycle.  See the docs.
# hooks_apply_watch       - OPTIONAL: While hooks are wired, print their "[<hook_name>] ..." serial-console lines into the apply output (needs the az CLI). Default = true.
node_hooks_files = {
  pre_run_file  = null
  post_run_file = null
  override_file = null
}

provisioner_hooks_files = {
  pre_run_file  = null
  post_run_file = null
  override_file = null
}

hooks_apply_watch = true

# ****************************** OPTIONAL ADVANCED SETTINGS *****************************
# disable_appconfig_public_network_access - (OPTIONAL) Disable public network access to the App Configuration instance the provider creates.
# disable_keyvault_public_network_access  - (OPTIONAL) Disable public network access to the Key Vault the provider creates or uses.
# networking_mode                         - (OPTIONAL) Network management mode for cluster nodes ("host_managed" default or "qumulo_managed").
# nsg_allow_ingress_icmp                  - (OPTIONAL) Enable ICMP ingress in the NSG rules the provider creates, for network diagnostics.
# persistent_storage_resource_group       - (OPTIONAL) Resource group containing persistent storage accounts and Key Vault, if different from resource_group_name.
# resource_group_name_suffix              - (OPTIONAL) Trailing label after the random uniqueness suffix in the resource group name (default "-rg"). Purely
#                                            cosmetic -- freeform, e.g. "-westus2" to match a region-based naming convention, or "" for none. Does NOT
#                                            affect the uniqueness guarantee; the random suffix itself is always present regardless of this setting.
# private_link_appconfig_dns_zone_id      - (OPTIONAL) Resource ID of the privatelink.azconfig.io private DNS zone.
# private_link_keyvault_dns_zone_id       - (OPTIONAL) Resource ID of the privatelink.vaultcore.azure.net private DNS zone.
# marketplace_image / provisioner_marketplace_image - (OPTIONAL) Azure Marketplace image specs. Defaults to Ubuntu if unset. See examples/azure-rhel.tf for a populated RHEL 8/9 example, e.g.:
#   marketplace_image = [{ publisher = "RedHat", offer = "RHEL", sku = "9-lvm-gen2", version = "latest" }]
# naming                                  - (OPTIONAL) Custom naming templates for Azure resources.
# nexus_api_token                         - (OPTIONAL) Qumulo Nexus API token (provider-level). When set, auto-mints nexus_registration_key and onboards to Nexus Fleet automatically.
# nexus_account_id                        - (OPTIONAL) Qumulo Nexus organization ID (provider-level). Only relevant when nexus_api_token is set; omit to auto-resolve from the token.
disable_appconfig_public_network_access = false
disable_keyvault_public_network_access  = false
networking_mode                         = null
nsg_allow_ingress_icmp                  = false
persistent_storage_resource_group       = null
resource_group_name_suffix              = "-rg"
private_link_appconfig_dns_zone_id      = null
private_link_keyvault_dns_zone_id       = null
marketplace_image                       = null
provisioner_marketplace_image           = null
naming                                  = null
nexus_api_token                         = null
nexus_account_id                        = null

# ***** OPTIONAL Cluster DNS *****
# cluster_fqdn - For clusters that want Qumulo Core to answer DNS queries directly with floating IPs (no separate DNS forwarder needed, unlike the AWS Route 53 Resolver pattern).
#                This may be left 'null' to bypass any FQDN DNS resolution on the Qumulo cluster.
cluster_fqdn = null
