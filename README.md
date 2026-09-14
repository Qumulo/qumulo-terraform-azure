<!-- BEGIN_TF_DOCS -->

<a target="_blank" href="https://qumulo.com/"><img src="./images/qumulo-scale-anywhere-logo.webp" style="width:150px;height:53px;"></a>

# Deploying Cloud Native Qumulo (CNQ) on Azure with Terraform

This repository contains Terraform which deploys a resource group, storage accounts, managed identities, and a CNQ cluster with 1 or 3+ node VMs, using the [Qumulo Terraform Provider](https://qumulo.github.io/terraform-provider-qumulo-cloud/) (`qumulo_filesystem_azure` resource).

This greatly simplifies Terraform operations versus hand-building the underlying Azure resources: the provider creates the resource group (if needed), managed identities, and Key Vault (if needed), and manages the VM Scale Set / node lifecycle, scaling, and upgrades for you. To learn more about the provider read the [provider docs](https://qumulo.github.io/terraform-provider-qumulo-cloud/).

> This repository was converted from Qumulo's [AWS CNQ Terraform](../qumulo-terraform-aws-main). Because the Azure provider resource handles multi-zone placement, floating IPs, and cluster DNS internally, there is no Azure equivalent of the AWS module's `nlb` and `route53-resolver` submodules -- those concerns are just attributes on `qumulo_filesystem_azure` (`availability_zones`, `floating_ip_count`, `cluster_fqdn`). The `secrets` module is preserved, backed by Azure Key Vault instead of AWS Secrets Manager.

## Prerequisites

- An existing Virtual Network and subnet. The subnet **must** have the `Microsoft.KeyVault` and `Microsoft.Storage` service endpoints enabled -- `main.tf` checks this and fails fast with a clear error if they're missing.
- Azure CLI login, a Service Principal, or a Managed Identity with rights to create resource groups, storage accounts, managed identities, Key Vault, and VMs in the target subscription.

## Configure Terraform backend.tf

This Terraform defaults to store state in Azure Blob Storage. As such the ./backend.tf must be configured with the storage account, resource group, and container you choose to store state in.
Note you can't put variables in the backend.tf config, which is why this note is here. If you call this Terraform as a module the backend.tf will be ignored.

## Getting Started with Cloud Native Qumulo (CNQ)

For the full resource schema, defaults, and examples, see the [Qumulo Terraform Provider documentation](https://qumulo.github.io/terraform-provider-qumulo-cloud/).

> ✅ **Tip:** For help with deployment, configuration, updates, scaling out your cluster, and best practices for high performance, [message us on Slack](https://docs.qumulo.com/contacting-qumulo-care-team.html).

---

### Standard Deployment Example

```hcl
module "cloud_native_qumulo" {
  source = "../"
  # ****************************** QUMULO PROVIDER VARIABLES ********************
  #-----------REQUIRED-------------------
  deployment_name       = "cnq-deploy-01"
  location              = "eastus2"
  resource_group_name   = "rg-qumulo"
  subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
  vm_type                = "Standard_L8s_v4"
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
    owner        = "owner"
    department   = "department"
    purpose      = "purpose"
    long_running = "true"
  }

  # ***** Qumulo Cluster Variables ******
  #-----------REQUIRED-------------------
  admin_pwd_or_keyvault_secret_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault_name>/secrets/<secret_name>"
  cluster_name                    = "CNQ-HOT"
  cluster_product_type            = "HOT"
  node_count                      = 3
  deletion_protection             = true

  #------------OPTIONAL------------------
  cluster_version          = null
  floating_ip_count        = 3
  nexus_registration_key   = null
  provider_timeout_minutes = 30
  storage_class            = null
  storage_replication_type = null
  soft_capacity_limit_tb   = null
}

output "outputs_cloud_native_qumulo" {
  value = module.cloud_native_qumulo
}
```

---

## Private networking (post-deployment)

The `create_storage_private_endpoint`, `create_keyvault_private_endpoint`, and
`create_appconfig_private_endpoint` flags select, per resource, which services get private
endpoints -- an environment can put storage and Key Vault behind private endpoints while App
Configuration stays public. One `terraform apply` deploys the cluster and takes the selected
services private-ready. The qumulo provider deploys with public network access **on** (so the
deployment never depends on private-name resolution) and creates the selected private endpoints --
one per storage account, one for the Key Vault, one for the App Configuration store -- as its
final step, with no DNS attached, reporting them in the `storage_private_endpoints`,
`keyvault_private_endpoint`, and `appconfig_private_endpoint` outputs. In the same apply, after the cluster completes, the wrapper:

1. Creates A records for the endpoints in your Azure Private DNS zones, when the
   `blob_/keyvault_/appconfig_private_dns_zone_id` variables are set -- the `modules/private-dns`
   module, structured like the AWS wrapper's `route53-resolver`: an optional post-cluster module
   that consumes the cluster's computed outputs. On the external-DNS path
   (e.g. Infoblox), leave the zone variables null and feed the `private_endpoints` output to your
   DNS system instead -- one A record `fqdn -> ip_address` per entry. (The App Configuration
   endpoint is safe to exist during and after deployment: Azure only auto-denies a store's public
   traffic on endpoint creation when its `publicNetworkAccess` property was never set, and the
   provider pins it to `Enabled`, so the store keeps its public path until the explicit lockdown.)
2. Links the zones to the cluster VNet (`manage_dns_zone_vnet_links`, default true) -- strictly
   after their records exist, because a linked privatelink zone is authoritative inside the VNet
   and an empty one turns the endpoint FQDNs into NXDOMAIN for the running cluster.
3. With `disable_public_network_access_post_deploy = true`, disables public network access on the storage accounts, the Key Vault (skipped for a
   customer-managed `key_vault_id` vault), and the App Configuration store -- the last step of the
   same apply, performed by the `modules/network-lockdown` module. That module boundary is
   deliberate: today its internals PATCH via the azapi provider; when the qumulo provider
   ships its planned network-lockdown resource, only the module internals change and the azapi
   dependency goes away. (`modules/private-dns` has the same property: if the provider later
   writes zone records itself via zone groups, that module is what shrinks or goes away.) Lockdown is only offered on the Azure DNS path (variable validation enforces the
   zone IDs): the wrapper closes public paths only when the same apply created and linked their
   private replacements. On the external-DNS path, **you own lockdown**: once your DNS serves the
   published records, disable public access from your own tooling -- every `private_endpoints`
   entry carries the `target_resource_id` to PATCH (`publicNetworkAccess = "Disabled"` on the
   storage accounts, Key Vault, and App Configuration store). There is deliberately no settle
   delay between the links and the lockdown: the cluster resolves names on every connection with
   no cache of its own, the node OS resolver holds the displaced public answers for at most 60
   seconds (their measured TTLs), and a connection that races the cutover fails against the closed
   public path and is retried -- the same transient-failure handling object-backed clusters rely
   on for normal cloud-storage weather. Expect up to a minute of retried-connection noise in node
   logs during the cutover, and nothing more.

> ⚠️ **Pre-linked zones:** the safe order above requires the wrapper to own the zone links. If a
> privatelink zone is **already** linked to the cluster VNet (a shared hub zone, or a second
> cluster in the same VNet), set `manage_dns_zone_vnet_links = false` -- and know that this
> deployment's endpoint FQDNs resolve NXDOMAIN inside the VNet from the moment the endpoints are
> created (mid-deployment) until the records land, which can fail the deployment itself. Prefer
> zones that are not yet linked to this VNet. The external-DNS path is unaffected.

> ⚠️ **After lockdown:** run applies that add capacity from a network that resolves and reaches
> the private endpoints -- a scale-up writes SAS definitions to the Key Vault data plane.
> To re-open public access later (e.g. before removing the private networking), note that
> `az storage account update` fails on intelligent-storage accounts (its full-resource PUT
> round-trips `accessTier: Smart`, which Azure rejects on write) -- use a raw PATCH instead:
> `az rest --method patch --url "https://management.azure.com<account-id>?api-version=2024-01-01"
> --body '{"properties":{"publicNetworkAccess":"Enabled"}}'`. `az keyvault update
> --public-network-access Enabled` and `az appconfig update --enable-public-network true` work
> as-is.
> **Destroy needs no special access and no re-enabling:** every resource destroy goes through the
> Azure control plane, which the lockdown does not affect. The lockdown resources deliberately
> perform no API call on destroy, so a wrapper destroy never re-opens public access either.
> During teardown the DNS records and links are removed before the cluster, so still-running
> nodes log storage-resolution errors for the final minutes -- harmless, everything is being
> deleted. One exception: with a customer-managed `key_vault_id` vault, the provider cleans up
> SAS material over that vault's data plane, so the runner must be able to reach the customer's
> own vault.

The subnet's Microsoft.Storage and Microsoft.KeyVault service endpoints stay required in every
mode: a private endpoint changes nothing about traffic until DNS points at it, so deployment and
scale-up traffic ride the service-endpoint path until the records exist.

Capacity scale-ups on the Azure DNS path extend everything in one apply: the provider adds
accounts and (last) their endpoints, the wrapper adds their records and, if lockdown is on, locks
the new accounts down. On the external-DNS path, a scale-up refreshes
the `private_endpoints` output; publish the new entries to your DNS, then lock the new account
down from your own tooling -- the new account stays reachable through the subnet's service
endpoint until you do.

## Terraform Documentation

> ℹ️ **Note:** Requirements, Inputs, and Outputs below are hand-maintained (this repository does not yet run `terraform-docs` in CI). Keep them in sync with `variables.tf` / `outputs.tf` when either changes.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 3.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | >= 3.1 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.1 |
| <a name="requirement_qumulo"></a> [qumulo](#requirement\_qumulo) | >= 1.4.15 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_pwd_or_keyvault_secret_id"></a> [admin\_pwd\_or\_keyvault\_secret\_id](#input\_admin\_pwd\_or\_keyvault\_secret\_id) | Provide either a plaintext administrator password, the resource ID of an Azure Key Vault secret (`<key_vault_resource_id>/secrets/<secret_name>`), or a Key Vault secret URI (`https://<vault>.vault.azure.net/secrets/<secret_name>/<version>`). The URI's optional `/<version>` segment is accepted but ignored -- Terraform always reads the secret's current/latest version, even if an older version is named. This value is write-only, so Terraform never stores it in state, but its current value is resupplied to the provider on every apply that touches this resource (not just creation), since node/vm\_type changes must authenticate to the existing cluster with it. It does NOT itself rotate an already-running cluster's password -- use the Qumulo UI or qumulo-cli to change the password after creation, and update the Key Vault secret to match (or vice versa) any time you do. **Warning:** there is no pre-flight check that this value matches an existing cluster's actual password -- if it has drifted out of sync, an apply that needs to authenticate to that cluster (scaling, vm\_type changes, etc.) can fail partway through with no automatic cleanup. Verify the two match before applying changes to an existing cluster. | `string` | n/a | yes |
| <a name="input_allow_cidrs"></a> [allow\_cidrs](#input\_allow\_cidrs) | OPTIONAL: CIDR blocks allowed to access the cluster. Defaults to the cluster subnet's address prefixes if not provided. | `list(string)` | `null` | no |
| <a name="input_appconfig_private_dns_zone_id"></a> [appconfig\_private\_dns\_zone\_id](#input\_appconfig\_private\_dns\_zone\_id) | OPTIONAL: Full resource ID of the `privatelink.azconfig.io` (public) / `privatelink.azconfig.azure.us` (US Gov) private DNS zone; the wrapper creates the App Configuration endpoint's A record. Requires `create_appconfig_private_endpoint`; same subscription as the other zones. | `string` | `null` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | OPTIONAL: Availability zones for deployment, e.g. `["1", "2", "3"]`. Omit for zoneless regions. Zone support is validated dynamically by the provider. | `list(string)` | `null` | no |
| <a name="input_azure_environment"></a> [azure\_environment](#input\_azure\_environment) | OPTIONAL: Azure cloud environment for the qumulo provider. | `string` | `"public"` | no |
| <a name="input_azure_subscription_id"></a> [azure\_subscription\_id](#input\_azure\_subscription\_id) | Azure subscription ID. Required -- the qumulo provider only falls back to the `ARM_SUBSCRIPTION_ID` environment variable, not the active Azure CLI context, so `az login` alone is not sufficient. | `string` | n/a | yes |
| <a name="input_blob_private_dns_zone_id"></a> [blob\_private\_dns\_zone\_id](#input\_blob\_private\_dns\_zone\_id) | OPTIONAL: Full resource ID of the `privatelink.blob.core.windows.net` (public) / `privatelink.blob.core.usgovcloudapi.net` (US Gov) private DNS zone; the wrapper creates one A record per storage-account private endpoint. Requires `create_storage_private_endpoint`; same subscription as the Key Vault zone. Leave null on the external-DNS (e.g. Infoblox) path. | `string` | `null` | no |
| <a name="input_cluster_fqdn"></a> [cluster\_fqdn](#input\_cluster\_fqdn) | OPTIONAL: Fully qualified domain name for Qumulo Core authoritative DNS. When set, the cluster answers DNS queries with floating IPs. | `string` | `null` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the Qumulo cluster as it appears in qfsd and the UI (2-15 characters; case preserved; dash allowed if not first or last character). | `string` | n/a | yes |
| <a name="input_cluster_node_identity_id"></a> [cluster\_node\_identity\_id](#input\_cluster\_node\_identity\_id) | OPTIONAL: Resource ID of a user-assigned managed identity for cluster nodes. If omitted, the provider creates one. | `string` | `null` | no |
| <a name="input_cluster_product_type"></a> [cluster\_product\_type](#input\_cluster\_product\_type) | Cluster storage product type (immutable after creation). HOT: Optimized for frequently accessed data. COLD: Optimized for archival/infrequently accessed data. | `string` | n/a | yes |
| <a name="input_cluster_stall_window"></a> [cluster\_stall\_window](#input\_cluster\_stall\_window) | OPTIONAL: How long the provisioner lets the cluster report no change at all before it gives up on a node addition, removal, or replacement -- a duration such as `"20m"`, `"45m"` or `"2h"`. Passed to the qumulo provider's cluster\_stall\_window; null keeps the provider default of 20m. This bounds silence, not work: while quorum, membership, or the restriper keep changing, the operation runs for as long as it needs, so there is no overall maximum. Raise it for clusters whose membership changes settle slowly. The provider refuses values under 1m and warns under 5m: a short window can abandon an apply partway through an operation that was still progressing, leaving the cluster mid-change. Requires provider 1.4.14 or later. | `string` | `null` | no |
| <a name="input_cluster_uuid"></a> [cluster\_uuid](#input\_cluster\_uuid) | OPTIONAL: UUID of an existing Qumulo cluster to import/adopt, for the rare case where the cluster's UUID cannot be auto-recovered. Leave null for new deployments. | `string` | `null` | no |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | OPTIONAL: Qumulo software version. Defaults to latest. Immutable after creation. Upgrade version via cluster UI/API. | `string` | `null` | no |
| <a name="input_create_appconfig_private_endpoint"></a> [create\_appconfig\_private\_endpoint](#input\_create\_appconfig\_private\_endpoint) | OPTIONAL: Private endpoint for the App Configuration store; leave false to keep it on its public endpoint -- see [Private networking (post-deployment)](#private-networking-post-deployment). Conflicts with the LEGACY `private_link_*` / `disable_*` variables. | `bool` | `false` | no |
| <a name="input_create_keyvault_private_endpoint"></a> [create\_keyvault\_private\_endpoint](#input\_create\_keyvault\_private\_endpoint) | OPTIONAL: Private endpoint for the Key Vault -- see [Private networking (post-deployment)](#private-networking-post-deployment). Conflicts with `key_vault_id` and the LEGACY `private_link_*` / `disable_*` variables. | `bool` | `false` | no |
| <a name="input_create_storage_private_endpoint"></a> [create\_storage\_private\_endpoint](#input\_create\_storage\_private\_endpoint) | OPTIONAL: Private endpoints for the cluster's storage accounts (one per account) -- see [Private networking (post-deployment)](#private-networking-post-deployment). Conflicts with the LEGACY `private_link_*` / `disable_*` variables. | `bool` | `false` | no |
| <a name="input_custom_image_id"></a> [custom\_image\_id](#input\_custom\_image\_id) | OPTIONAL: Custom VM image resource ID for cluster nodes. If omitted, the default Qumulo image (Ubuntu) is used. | `string` | `null` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Protects the cluster's VMs and storage accounts from deletion with CanNotDelete management locks. | `bool` | `true` | no |
| <a name="input_deployment_name"></a> [deployment\_name](#input\_deployment\_name) | Lowercase seed for Azure resource names (2-15 characters: lowercase letters, digits, interior hyphens). | `string` | n/a | yes |
| <a name="input_disable_appconfig_public_network_access"></a> [disable\_appconfig\_public\_network\_access](#input\_disable\_appconfig\_public\_network\_access) | LEGACY: Disable public network access to the App Configuration instance the provider creates. Requires `private_link_appconfig_dns_zone_id`. Superseded by the `create_*_private_endpoint` variables + `disable_public_network_access_post_deploy`. | `bool` | `false` | no |
| <a name="input_disable_keyvault_public_network_access"></a> [disable\_keyvault\_public\_network\_access](#input\_disable\_keyvault\_public\_network\_access) | LEGACY: Disable public network access to the Key Vault the provider creates or uses. Requires `private_link_keyvault_dns_zone_id`. Superseded by the `create_*_private_endpoint` variables + `disable_public_network_access_post_deploy`. | `bool` | `false` | no |
| <a name="input_disable_public_network_access_post_deploy"></a> [disable\_public\_network\_access\_post\_deploy](#input\_disable\_public\_network\_access\_post\_deploy) | OPTIONAL: Disable public access, as the last step of the apply, on each service whose `create_*_private_endpoint` flag is set. Azure DNS path only (each enabled service needs its zone ID); external-DNS callers lock down from their own tooling via the `private_endpoints` output. | `bool` | `false` | no |
| <a name="input_floating_ip_count"></a> [floating\_ip\_count](#input\_floating\_ip\_count) | OPTIONAL: Number of floating IPs to assign to the cluster. Must be 0 (disabled) or between 3 and 100. Requires networking\_mode "host\_managed". Once a count has been applied, omitting this attribute keeps the previous value -- set it to 0 explicitly to remove floating IPs. | `number` | `3` | no |
| <a name="input_key_vault_id"></a> [key\_vault\_id](#input\_key\_vault\_id) | OPTIONAL: Full Azure resource ID of a customer-managed Key Vault. If omitted, the provider creates one. | `string` | `null` | no |
| <a name="input_keyvault_private_dns_zone_id"></a> [keyvault\_private\_dns\_zone\_id](#input\_keyvault\_private\_dns\_zone\_id) | OPTIONAL: Full resource ID of the `privatelink.vaultcore.azure.net` (public) / `privatelink.vaultcore.usgovcloudapi.net` (US Gov) private DNS zone; the wrapper creates the Key Vault endpoint's A record. Requires `create_keyvault_private_endpoint`; same subscription as the blob zone. Leave null on the external-DNS path. | `string` | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for deployment | `string` | n/a | yes |
| <a name="input_manage_dns_zone_vnet_links"></a> [manage\_dns\_zone\_vnet\_links](#input\_manage\_dns\_zone\_vnet\_links) | OPTIONAL: Link the supplied privatelink zones to the cluster VNet, after their records exist. Set false when the zones are already linked to this VNet (pre-linked hazard applies). | `bool` | `true` | no |
| <a name="input_marketplace_image"></a> [marketplace\_image](#input\_marketplace\_image) | OPTIONAL: Azure Marketplace image specification for cluster nodes. | `list(object({ publisher = string, offer = string, sku = string, version = string }))` | `null` | no |
| <a name="input_naming"></a> [naming](#input\_naming) | OPTIONAL: Custom naming templates for Azure resources. | `list(object({ storage_account = optional(string), vm_name = optional(string) }))` | `null` | no |
| <a name="input_networking_mode"></a> [networking\_mode](#input\_networking\_mode) | OPTIONAL: Network management mode for cluster nodes ("host\_managed" default or "qumulo\_managed"). | `string` | `null` | no |
| <a name="input_nexus_account_id"></a> [nexus\_account\_id](#input\_nexus\_account\_id) | OPTIONAL: Qumulo Nexus organization ID to onboard newly-created clusters to. Only relevant when nexus\_api\_token is set; omit to let the provider auto-resolve the organization from the token's binding. | `number` | `null` | no |
| <a name="input_nexus_api_token"></a> [nexus\_api\_token](#input\_nexus\_api\_token) | OPTIONAL: Qumulo Nexus API token. When set, the provider auto-mints nexus\_registration\_key and onboards new clusters to Nexus Fleet automatically; any value supplied to nexus\_registration\_key is ignored. Leave null (with nexus\_registration\_key) to skip Nexus onboarding entirely. | `string` | `null` | no |
| <a name="input_nexus_registration_key"></a> [nexus\_registration\_key](#input\_nexus\_registration\_key) | OPTIONAL: (Deprecated) Qumulo Nexus registration key for remote support. Ignored when nexus\_api\_token is set on the provider. | `string` | `null` | no |
| <a name="input_node_count"></a> [node\_count](#input\_node\_count) | Number of nodes in the cluster. Valid values: 1 (single node), or 3-24. 2 is not supported, and 4 requires a single availability zone. | `number` | n/a | yes |
| <a name="input_node_hooks_files"></a> [node\_hooks\_files](#input\_node\_hooks\_files) | OPTIONAL: Advanced use only. Filenames (relative to the hooks/ directory) spliced into each node's boot script at pre\_run\_file / post\_run\_file anchors. Runs only on first boot. `override_file` replaces the entire node boot script. | `object({ pre_run_file = optional(string), post_run_file = optional(string), override_file = optional(string) })` | `null` | no |
| <a name="input_nsg_allow_ingress_icmp"></a> [nsg\_allow\_ingress\_icmp](#input\_nsg\_allow\_ingress\_icmp) | OPTIONAL: Enable ICMP ingress in the NSG rules the provider creates, for network diagnostics. | `bool` | `false` | no |
| <a name="input_persistent_storage_resource_group"></a> [persistent\_storage\_resource\_group](#input\_persistent\_storage\_resource\_group) | OPTIONAL: Resource group containing persistent storage accounts and Key Vault, if different from resource\_group\_name. | `string` | `null` | no |
| <a name="input_private_link_appconfig_dns_zone_id"></a> [private\_link\_appconfig\_dns\_zone\_id](#input\_private\_link\_appconfig\_dns\_zone\_id) | LEGACY: Resource ID of the privatelink.azconfig.io private DNS zone; the provider creates the App Configuration private endpoint bound to it during deployment. Superseded by the `create_*_private_endpoint` variables. | `string` | `null` | no |
| <a name="input_private_link_keyvault_dns_zone_id"></a> [private\_link\_keyvault\_dns\_zone\_id](#input\_private\_link\_keyvault\_dns\_zone\_id) | LEGACY: Resource ID of the privatelink.vaultcore.azure.net private DNS zone; the provider creates the Key Vault private endpoint bound to it during deployment. Superseded by the `create_*_private_endpoint` variables. | `string` | `null` | no |
| <a name="input_provider_create_timeout_minutes"></a> [provider\_create\_timeout\_minutes](#input\_provider\_create\_timeout\_minutes) | OPTIONAL: Timeout override (in minutes) for cluster creation. Defaults to provider\_timeout\_minutes if unset. The provider's own built-in default (used only if the whole timeouts block were omitted) is 90 minutes. | `number` | `null` | no |
| <a name="input_provider_delete_timeout_minutes"></a> [provider\_delete\_timeout\_minutes](#input\_provider\_delete\_timeout\_minutes) | OPTIONAL: Timeout override (in minutes) for cluster deletion. Defaults to provider\_timeout\_minutes if unset. The provider's own built-in default (used only if the whole timeouts block were omitted) is 30 minutes. | `number` | `null` | no |
| <a name="input_provider_timeout_minutes"></a> [provider\_timeout\_minutes](#input\_provider\_timeout\_minutes) | The default timeout (in minutes) applied to any of create/update/delete not individually overridden by provider\_create\_timeout\_minutes / provider\_update\_timeout\_minutes / provider\_delete\_timeout\_minutes. | `number` | `30` | no |
| <a name="input_provider_update_timeout_minutes"></a> [provider\_update\_timeout\_minutes](#input\_provider\_update\_timeout\_minutes) | OPTIONAL: Timeout override (in minutes) for cluster updates (e.g. scaling, vm\_type changes). Defaults to provider\_timeout\_minutes if unset. The provider's own built-in default (used only if the whole timeouts block were omitted) is 60 minutes. | `number` | `null` | no |
| <a name="input_provisioner_custom_image_id"></a> [provisioner\_custom\_image\_id](#input\_provisioner\_custom\_image\_id) | OPTIONAL: Custom VM image resource ID for the provisioner instance. Defaults to the default Qumulo image. | `string` | `null` | no |
| <a name="input_provisioner_hooks_files"></a> [provisioner\_hooks\_files](#input\_provisioner\_hooks\_files) | OPTIONAL: Advanced use only. Filenames (relative to the hooks/ directory) spliced into the provisioner's boot script at pre\_run\_file / post\_run\_file anchors. `override_file` replaces the entire provisioner boot script. | `object({ pre_run_file = optional(string), post_run_file = optional(string), override_file = optional(string) })` | `null` | no |
| <a name="input_provisioner_identity_id"></a> [provisioner\_identity\_id](#input\_provisioner\_identity\_id) | OPTIONAL: Resource ID of a user-assigned managed identity for the provisioner VM. If omitted, the provider creates one. | `string` | `null` | no |
| <a name="input_provisioner_marketplace_image"></a> [provisioner\_marketplace\_image](#input\_provisioner\_marketplace\_image) | OPTIONAL: Azure Marketplace image specification for the provisioner VM. | `list(object({ publisher = string, offer = string, sku = string, version = string }))` | `null` | no |
| <a name="input_provisioner_vm_type"></a> [provisioner\_vm\_type](#input\_provisioner\_vm\_type) | OPTIONAL: Azure VM size for the provisioner instance (used during deploy operations). Defaults to the provider's built-in default. | `string` | `null` | no |
| <a name="input_provisioning_timeout_minutes"></a> [provisioning\_timeout\_minutes](#input\_provisioning\_timeout\_minutes) | OPTIONAL, DEPRECATED: ignored by provider 1.4.15 and later, which bound create, scale, and replacement only by the operation timeouts (provider\_timeout\_minutes and the per-operation provider\_\*\_timeout\_minutes overrides) plus cluster\_stall\_window for cluster-side stalls. Still passed through for configuration compatibility; remove it from configurations and size provider\_timeout\_minutes for the platform's worst case instead. | `number` | `null` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of this deployment's Azure resource group, used exactly as given. The provider creates the group if absent; alternatively, pre-create it -- along with resources for the deployment such as the Key Vault (see `key_vault_id`) -- when RBAC grants or policy exemptions must exist before the first apply. Do not share the group with any other VMs. **On Qumulo Core versions below 7.10.1 this is a hard requirement**: the floating-IP reconciler on those versions strips secondary IPs from every NIC in the group it does not recognize (a plan-time warning reports this whenever the version to be installed -- explicit `cluster_version` or auto-selected latest -- is below 7.10.1). Versions 7.10.1 and later touch only addresses the cluster owns. | `string` | n/a | yes |
| <a name="input_soft_capacity_limit_tb"></a> [soft\_capacity\_limit\_tb](#input\_soft\_capacity\_limit\_tb) | OPTIONAL: Soft capacity limit in TB (50 to 10000). Default is 500TB. Can be increased to add storage, but cannot be decreased. It's like a quota, unused capacity is not billed. | `number` | `500` | no |
| <a name="input_ssh_public_key_path"></a> [ssh\_public\_key\_path](#input\_ssh\_public\_key\_path) | OPTIONAL: Path to a local SSH public key file for SSH access to cluster nodes, e.g. `"~/.ssh/id_rsa.pub"`. The file's contents are read and passed to the provider; `~` is expanded to the home directory. Do not set this to the key content itself. | `string` | `null` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | OPTIONAL: Storage backing the cluster's persistent data. HOT supports STANDARD and INTELLIGENT\_TIERING. Defaults to the provider's built-in default for the chosen cluster\_product\_type. | `string` | `null` | no |
| <a name="input_storage_replication_type"></a> [storage\_replication\_type](#input\_storage\_replication\_type) | OPTIONAL: Azure storage replication type (immutable after creation). LRS or ZRS. | `string` | `null` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Full Azure resource ID of the subnet. The cluster's storage accounts are restricted to this subnet. The subnet must have the Microsoft.KeyVault and Microsoft.Storage service endpoints enabled. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | OPTIONAL: Tags to apply to all Azure resources created for this cluster. | `map(string)` | `null` | no |
| <a name="input_vm_type"></a> [vm\_type](#input\_vm\_type) | Azure VM size for cluster nodes. Only L-series storage-optimized VMs are supported (e.g. Standard\_L8s\_v4). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the Qumulo cluster |
| <a name="output_cluster_uuid"></a> [cluster\_uuid](#output\_cluster\_uuid) | UUID of the Qumulo cluster |
| <a name="output_deployment_unique_name"></a> [deployment\_unique\_name](#output\_deployment\_unique\_name) | Unique deployment identifier |
| <a name="output_endpoint_ips"></a> [endpoint\_ips](#output\_endpoint\_ips) | Client-facing IPs. Floating IPs if configured, otherwise primary node IPs. |
| <a name="output_endpoints"></a> [endpoints](#output\_endpoints) | Connection endpoints for various protocols |
| <a name="output_private_dns_records"></a> [private\_dns\_records](#output\_private\_dns\_records) | fqdn -> private IP of the Azure Private DNS A records the wrapper created. Empty on the external-DNS path. |
| <a name="output_private_endpoints"></a> [private\_endpoints](#output\_private\_endpoints) | Descriptors of every private endpoint serving this deployment (storage accounts, Key Vault, App Configuration). The feed for external DNS systems such as Infoblox. |
| <a name="output_primary_ips"></a> [primary\_ips](#output\_primary\_ips) | Per-node primary IPs. Use these directly when no floating IPs are configured, or for per-node access. |
| <a name="output_resource_group_unique_name"></a> [resource\_group\_unique\_name](#output\_resource\_group\_unique\_name) | The deployment's Azure resource group name (`resource_group_name` verbatim; retained under this name so existing tooling keeps working). |
| <a name="output_soft_capacity_limit_tb"></a> [soft\_capacity\_limit\_tb](#output\_soft\_capacity\_limit\_tb) | Total capacity the cluster may consume.  Only used capacity is billed. |

---

## About This Repository
This repository uses the [MIT license](LICENSE). All contents Copyright &copy; 2026 [Qumulo, Inc.](https://qumulo.com), except where specified. All trademarks are property of their respective owners.
<!-- END_TF_DOCS -->
