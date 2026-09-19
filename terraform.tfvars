# ****************************** QUMULO PROVIDER VARIABLES ********************
# *********** Azure Variables ***********
# deployment_name               - A name for this deployment, lowercase letters, digits, and interior hyphens, 2-15 characters.
# location                      - Azure region for deployment.
# resource_group_name           - Name of this deployment's Azure resource group, used exactly as given. Either let the provider create it, or
#                                 pre-create it (along with resources like the Key Vault, see key_vault_id) when RBAC grants or policy exemptions
#                                 must exist before the first apply. Do not share the group with any other VMs. On Qumulo Core versions below
#                                 7.10.1 this is a hard requirement (a plan/apply warning reports it): no other clusters or VMs in the group.
# subnet_id                     - Full Azure resource ID of the pre-configured subnet for cluster nodes. Must have the Microsoft.KeyVault and Microsoft.Storage service endpoints enabled.
# vm_type                       - Azure VM size for cluster nodes. Only L-series storage-optimized VMs are supported (e.g. Standard_L8s_v4).
# azure_subscription_id         - Azure subscription ID. The qumulo provider only falls back to the ARM_SUBSCRIPTION_ID environment variable, not the
#                                  active Azure CLI context, so `az login` alone is not enough -- set this explicitly.
# allow_cidrs                   - (OPTIONAL) CIDR blocks allowed to access the cluster (the subnet's address prefixes are used by default). Production clusters should restrict to known client/management networks. ie: 10.0.1.0/24
# availability_zones            - (OPTIONAL) Availability zones for deployment, e.g. ["1", "2", "3"]. Omit for zoneless regions.
# azure_environment             - (OPTIONAL) Azure cloud environment for the qumulo provider. "public" or "usgovernment". Default = "public".
# cluster_node_identity_id      - (OPTIONAL) Resource ID of a user-assigned managed identity for cluster nodes. If omitted, the provider creates one.
# custom_image_id               - (OPTIONAL) Custom VM image resource ID for cluster nodes. Also supplies the provisioner's image -- there is no
#                                 separate provisioner_custom_image_id. If omitted, the default Qumulo image (Ubuntu) is used.
# key_vault_id                  - (OPTIONAL) Full Azure resource ID of a customer-managed Key Vault. If omitted, the provider creates one.
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
allow_cidrs              = null
availability_zones       = ["1", "2", "3"]
azure_environment        = "public"
cluster_node_identity_id = null
custom_image_id          = null
key_vault_id             = null
provisioner_identity_id  = null
provisioner_vm_type      = null
ssh_public_key_path      = null
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
# provider_timeout_minutes       - (OPTIONAL) The default timeout, in minutes, applied to any of create/update/delete not overridden individually below. Default is 30 minutes.
# provider_create_timeout_minutes - (OPTIONAL) Timeout override for cluster creation, in minutes. Defaults to provider_timeout_minutes if unset. Consider raising this for larger node_count deployments.
# provider_update_timeout_minutes - (OPTIONAL) Timeout override for cluster updates (scaling, vm_type changes), in minutes. Defaults to provider_timeout_minutes if unset.
# provider_delete_timeout_minutes - (OPTIONAL) Timeout override for cluster deletion, in minutes. Defaults to provider_timeout_minutes if unset.
# provisioning_timeout_minutes    - (OPTIONAL, DEPRECATED) Ignored by provider 1.4.15 and later; all operations are bounded by the provider_*_timeout_minutes
#                                    values plus cluster_stall_window. Leave null and size provider_timeout_minutes for the platform's worst case instead.
# cluster_stall_window           - (OPTIONAL) How long a node addition, removal, or replacement may show no cluster activity (quorum, membership,
#                                    restriper) before the provisioner gives up, e.g. "20m", "45m", "2h". Null = the provider default of 20m. Bounds silence,
#                                    not work: an operation that keeps progressing runs as long as it needs. Provider 1.4.14 or later.
# node_replacement_when_changed  - (OPTIONAL) Pure change-trigger, not a real setting -- its value is never inspected. Edit it to any new value
#                                    (with no other change) to force a full cluster replace, node by node, same vm_type and node_count. Use this
#                                    to pick up a disk-layout or tunable fix that only applies to newly-built nodes. Leave null to do nothing.
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
provider_timeout_minutes        = 30
provider_create_timeout_minutes = null
provider_update_timeout_minutes = null
provider_delete_timeout_minutes = null
provisioning_timeout_minutes    = null
cluster_stall_window            = null
node_replacement_when_changed   = null
storage_class                   = null
storage_replication_type        = null
soft_capacity_limit_tb          = 100

# ***** Miscellaneous Variables *******
# If boot behavior needs to be completely overridden contact support@qumulo.com or your Qumulo SE/SA.  Typically most needs can be accomodated with these pre/post hooks.  Hooks look in the hooks/ directory for the file.
# node_hooks_files        - OPTIONAL: Advanced use only.  Hooks run pre-boot-network or post-qumulo-core-install. override_file completely replaces the boot script. Executed only on first boot cycle.  See the docs.
#                           pre_run_files/post_run_files (lists) chain several hooks in order; see hooks/readme.md.
#                           The included hooks/wait-for-rhel-entitlement.sh (as pre_run_file) blocks RHEL BYOS node boot until subscription content is available; see hooks/readme.md.
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
# disable_keyvault_public_network_access  - (OPTIONAL) Disable public network access to the Key Vault the provider creates.
# networking_mode                         - (OPTIONAL) Network management mode for cluster nodes ("host_managed" default or "qumulo_managed").
# nsg_allow_ingress_icmp                  - (OPTIONAL) Enable ICMP ingress in the NSG rules the provider creates, for network diagnostics.
# persistent_storage_resource_group       - (OPTIONAL) Resource group containing persistent storage accounts and Key Vault, if different from resource_group_name.
# private_link_appconfig_dns_zone_id      - (OPTIONAL) Resource ID of the privatelink.azconfig.io private DNS zone.
# private_link_keyvault_dns_zone_id       - (OPTIONAL) Resource ID of the privatelink.vaultcore.azure.net private DNS zone.
# marketplace_image / provisioner_marketplace_image - (OPTIONAL) Azure Marketplace image specs. Defaults to Ubuntu if unset. See examples/azure-rhel.tf for a populated RHEL 8/9 example, e.g.:
#   marketplace_image = [{ publisher = "RedHat", offer = "RHEL", sku = "9-lvm-gen2", version = "latest" }]
# naming                                  - (OPTIONAL) Custom naming templates for Azure resources.
# nexus_api_token_or_keyvault_secret_id   - (OPTIONAL) Qumulo Nexus API token (provider-level), as plaintext, a Key Vault secret resource ID, or a Key Vault secret
#                                            URI -- resolved the same way as admin_pwd_or_keyvault_secret_id. When set, auto-mints a per-cluster Nexus registration
#                                            key and onboards to Nexus Fleet automatically.
# nexus_account_id                        - (OPTIONAL) Qumulo Nexus organization ID (provider-level). Only relevant when nexus_api_token_or_keyvault_secret_id is set; omit to auto-resolve from the token.
# disable_appconfig_public_network_access = true
# disable_keyvault_public_network_access  = true
networking_mode                       = null
nsg_allow_ingress_icmp                = false
persistent_storage_resource_group     = null
private_link_appconfig_dns_zone_id    = null
private_link_keyvault_dns_zone_id     = null
marketplace_image                     = null
provisioner_marketplace_image         = null
naming                                = null
nexus_api_token_or_keyvault_secret_id = null
nexus_account_id                      = null

# ***** OPTIONAL Cluster DNS *****
# cluster_fqdn - For clusters that want Qumulo Core to answer DNS queries directly with floating IPs (no separate DNS forwarder needed, unlike the AWS Route 53 Resolver pattern).
#                This may be left 'null' to bypass any FQDN DNS resolution on the Qumulo cluster.
cluster_fqdn = null

# ***** OPTIONAL PRIVATE NETWORKING (post-deployment) *****
# One apply deploys the cluster (public access on; the provider creates the private
# endpoints for the storage accounts, Key Vault, and App Configuration as its final step,
# no DNS attached), then -- in the same apply -- the wrapper creates the Azure Private DNS
# A records (if the zone IDs are set), links the zones to the cluster VNet after the
# records exist, and -- with disable_public_network_access_post_deploy set -- disables
# public access as the last step. On the external-DNS path (e.g. Infoblox), leave the zone
# IDs null and feed the private_endpoints output to your DNS system; lockdown is then yours
# (fqdn/ip_address for records, target_resource_id for the publicNetworkAccess PATCH).
# See README "Private networking (post-deployment)".
# create_storage_private_endpoint           - (OPTIONAL) Private endpoints for the storage accounts (one per account). Conflicts with the legacy private_link_*/disable_* variables above.
# create_keyvault_private_endpoint          - (OPTIONAL) Private endpoint for the Key Vault. Conflicts with key_vault_id and the legacy variables.
# create_appconfig_private_endpoint         - (OPTIONAL) Private endpoint for the App Configuration store. Leave false to keep App Configuration on its public endpoint.
# blob_private_dns_zone_id                  - (OPTIONAL) privatelink.blob.core.windows.net zone resource ID for wrapper-created A records.
# keyvault_private_dns_zone_id              - (OPTIONAL) privatelink.vaultcore.azure.net zone resource ID. Same subscription as the blob zone.
# appconfig_private_dns_zone_id             - (OPTIONAL) privatelink.azconfig.io zone resource ID for the App Configuration endpoint record. Same subscription as the other zones.
# manage_dns_zone_vnet_links                - (OPTIONAL, default true) Link the supplied zones to the cluster VNet after their records exist; false when pre-linked.
# disable_public_network_access_post_deploy - (OPTIONAL) Disable public access on storage/Key Vault/App Configuration as the apply's last step. Azure DNS path only.
create_storage_private_endpoint           = false
create_keyvault_private_endpoint          = false
create_appconfig_private_endpoint         = false
blob_private_dns_zone_id                  = null
keyvault_private_dns_zone_id              = null
appconfig_private_dns_zone_id             = null
disable_public_network_access_post_deploy = false
