# CNQ least-privilege permissions: Azure Portal walkthrough

This document builds the same roles, identities, and assignments as the
Terraform in this directory, one step at a time in the Azure Portal, and
explains why each right exists as you add it. Use it when your RBAC team works
in the Portal, when grants need change-review one at a time, or as the
reference for what the Terraform creates and why.

Every permission below was derived from what the qumulo provider, the wrapper,
and Qumulo Core actually call, and verified by live deployments running under
exactly these grants -- create, scale, node replacement, and destroy.

## What you will create

| Object | Scope | Held by |
|---|---|---|
| Resource group | -- | the deployment |
| Managed identity `<rg>-node` | lives in the resource group | cluster node VMs |
| Managed identity `<rg>-provisioner` | lives in the resource group | provisioner VM |
| Custom role `Qumulo CNQ Deployer` | deployment resource group | deployer principal |
| Custom role `Qumulo CNQ Deployer Subscription` | subscription | deployer principal |
| Custom role `Qumulo CNQ Deployer Network` | virtual network | deployer principal |
| Custom role `Qumulo CNQ Cluster Node` | deployment resource group | node identity |
| Custom role `Qumulo CNQ Subnet Join` | virtual network | node identity |
| Built-in role assignments | see step 7 | node + provisioner identities, operators |

The deployer principal is whatever runs `terraform` -- a user, a service
principal, or the managed identity of a runner VM. (The Terraform in this
directory creates a `<rg>-deployer` managed identity for that purpose by
default; in the Portal, decide up front which principal deploys.)

## Before you start

You need rights to create resource groups, managed identities, custom roles,
and role assignments at the scopes involved -- in practice, Owner or
Contributor + User Access Administrator on the subscription. This is the
one-time privileged step; nothing after it runs privileged.

Have on hand: the subscription ID, a name for the deployment resource group,
the resource ID of the cluster subnet, and the object ID of the deployer
principal. Object IDs come from the az CLI: `az ad signed-in-user show --query
id -o tsv` (yourself), `az ad user show --id person@example.com --query id -o
tsv` (another user), `az ad sp show --id <appId> --query id -o tsv` (a service
principal), or `az identity show -g <rg> -n <name> --query principalId -o tsv`
(a managed identity).

## Step 1: Create the deployment resource group

Portal: **Resource groups → Create.** Pick the region the cluster will deploy
into.

Why pre-created: the deployer's role is scoped to this group, so the group
must exist before the role can be defined on it -- and a pre-created group is
also where your organization can attach RBAC grants and policy exemptions
before the first `terraform apply`. Keep the group dedicated to one
deployment.

## Step 2: Create the managed identities

Portal: **Managed Identities → Create**, twice, in the deployment resource
group: one for the cluster nodes (e.g. `<rg>-node`) and one for the
provisioner (e.g. `<rg>-provisioner`).

Why they exist: supplying pre-created identities to the wrapper
(`cluster_node_identity_id`, `provisioner_identity_id`) makes the provider
skip all of its own role administration -- without them, it assigns broad
built-in roles (Virtual Machine Contributor, Network Contributor) to
system-assigned identities and creates a custom role at subscription scope,
which requires the deployer to hold `Microsoft.Authorization` write at the
subscription. Pre-creating the identities is what makes a least-privilege
deployer possible.

- The **node identity** is the cluster's runtime identity: Qumulo Core uses it
  to manage floating IPs and to read secrets and storage.
- The **provisioner identity** belongs to the short-lived VM that configures
  the cluster and reports progress.

## Step 3: Custom role "Qumulo CNQ Deployer" (resource group)

Portal: the resource group → **Access control (IAM) → Add → Add custom role →
JSON tab**, paste, then Review + create. Replace `<subscription-id>` and
`<resource-group>`.

```json
{
  "properties": {
    "roleName": "Qumulo CNQ Deployer (<resource-group>)",
    "description": "Minimum resource-group permissions to deploy and operate a CNQ cluster.",
    "assignableScopes": [
      "/subscriptions/<subscription-id>/resourceGroups/<resource-group>"
    ],
    "permissions": [
      {
        "actions": [
          "Microsoft.Resources/subscriptions/resourceGroups/read",
          "Microsoft.Resources/subscriptions/resourceGroups/write",
          "Microsoft.Compute/virtualMachines/read",
          "Microsoft.Compute/sshPublicKeys/read",
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
          "Microsoft.Insights/DataCollectionRuleAssociations/Delete"
        ],
        "notActions": [],
        "dataActions": [
          "Microsoft.KeyVault/vaults/secrets/getSecret/action",
          "Microsoft.KeyVault/vaults/secrets/setSecret/action",
          "Microsoft.KeyVault/vaults/secrets/readMetadata/action",
          "Microsoft.KeyVault/vaults/storageaccounts/read",
          "Microsoft.KeyVault/vaults/storageaccounts/set/action",
          "Microsoft.KeyVault/vaults/storageaccounts/delete",
          "Microsoft.KeyVault/vaults/storageaccounts/sas/read",
          "Microsoft.KeyVault/vaults/storageaccounts/sas/set/action",
          "Microsoft.KeyVault/vaults/storageaccounts/sas/delete"
        ],
        "notDataActions": []
      }
    ]
  }
}
```

Why each block:

- **Resource group read/write.** The provider reads the group on every
  operation and writes it to update deployment tags. Delete is deliberately
  absent: this model pre-creates the group, and the provider only deletes
  groups it created itself.
- **Virtual machines, disks, extensions.** The cluster nodes and the
  provisioner VM, their OS and data disks, and the Azure Monitor agent
  extension the provider installs on the provisioner for log streaming.
- **NICs, NSGs, ASGs, public IPs, and their join actions.** The provider
  creates these directly. In Azure, creating a resource that *references*
  another requires a join action on the referenced resource: a NIC that sits
  behind a network security group needs `networkSecurityGroups/join/action`, an
  IP configuration that joins an application security group needs
  `applicationSecurityGroups/joinIpConfiguration/action`, and so on. Public IP
  rights cover deployments with public endpoints.
- **Private endpoints and DNS zone groups.** Created when private-endpoint
  options are enabled. Creating a private endpoint also auto-approves its
  connection on the target service, and Azure checks that as a linked
  authorization on the target: without
  `PrivateEndpointConnectionsApproval/action` on the storage account, vault, or
  App Configuration store, the endpoint PUT fails with
  `LinkedAuthorizationFailed` even though `privateEndpoints/write` is granted.
- **Storage accounts, containers, listKeys.** The cluster's object storage.
  `listKeys` exists because the provider signs SAS definitions with an account
  key and stores them in Key Vault for the cluster's data path; the key itself
  never leaves the deployment flow.
- **Key Vault and App Configuration (management plane).** The provider creates
  a vault for cluster secrets and an App Configuration store for provisioning
  status. The `keyValues` actions are how it reads and writes status entries
  through ARM: `keyValues/action` is Azure's read operation for that API --
  there is no `keyValues/read` management action.
- **Managed identity read/write/assign.** `assign/action` attaches the
  pre-created identities to the VMs; `read` resolves their client IDs; `write`
  lets the provider keep identity tags in step with deployment tags.
- **Role assignments (read/write/delete) and permissions/read.** The one
  Authorization grant that cannot be dropped: on every create, the provider
  grants the terraform principal App Configuration Data Reader on the store it
  just created, and fails the deployment if that grant fails. The store does
  not exist before the deployment, so the assignment cannot be pre-created.
  Scoped to this resource group only. `permissions/read` serves the provider's
  own permission pre-check.
- **Log Analytics and data collection.** The provisioner streams its log to a
  Log Analytics workspace through a data collection endpoint and rule.
  `workspaces/sharedKeys/action` looks out of place but is required: Azure
  validates it when a data collection rule is created against the workspace,
  and without it the provider silently skips log streaming and the deployment
  produces no provisioner log.
- **Data actions (Key Vault data plane).** The provider creates the vault with
  RBAC authorization and immediately uses the data plane as the terraform
  principal: it stores the cluster admin password and per-storage-account SAS
  definitions (the `storageaccounts`/`sas` entries are the vault's managed
  storage account API). The wrapper also reads the admin password back when
  it is supplied as a Key Vault reference. The delete entries cover cleanup
  of SAS definitions at destroy.
- **Locks (only if you enable deletion protection).** Management locks live
  under `Microsoft.Authorization`, which Contributor does not carry. Add
  `Microsoft.Authorization/locks/read`, `/write`, and `/delete` to the actions
  list only when the wrapper's `deletion_protection` is on.

## Step 4: Custom role "Qumulo CNQ Deployer Subscription" (subscription)

Portal: the subscription → **Access control (IAM) → Add → Add custom role →
JSON tab**.

```json
{
  "properties": {
    "roleName": "Qumulo CNQ Deployer Subscription (<resource-group>)",
    "description": "Subscription-level reads and soft-delete purges for CNQ deployment.",
    "assignableScopes": ["/subscriptions/<subscription-id>"],
    "permissions": [
      {
        "actions": [
          "Microsoft.Resources/subscriptions/read",
          "Microsoft.Resources/subscriptions/resources/read",
          "Microsoft.Compute/skus/read",
          "Microsoft.KeyVault/deletedVaults/read",
          "Microsoft.KeyVault/locations/deletedVaults/read",
          "Microsoft.KeyVault/locations/deletedVaults/purge/action",
          "Microsoft.AppConfiguration/locations/deletedConfigurationStores/read",
          "Microsoft.AppConfiguration/locations/deletedConfigurationStores/purge/action"
        ],
        "notActions": [],
        "dataActions": [],
        "notDataActions": []
      }
    ]
  }
}
```

Why: these operations have no resource-group scope. The subscription read
serves tenant discovery when the provider's clients start; `resources/read`
lets the wrapper find a Key Vault by name when the admin password is supplied
as a vault URI; `skus/read` validates the requested VM size. The four
soft-delete entries let the provider purge a soft-deleted vault or App
Configuration store when a deployment is recreated under the same name --
without them, a redeploy after destroy stalls on name collisions until the
purge is done by hand. If your policy forbids purge rights, omit those four
entries and plan on manual purges.

## Step 5: Custom roles at the virtual network

Portal: the virtual network → **Access control (IAM) → Add → Add custom role →
JSON tab**, twice.

```json
{
  "properties": {
    "roleName": "Qumulo CNQ Deployer Network (<resource-group>)",
    "description": "Read and join the CNQ cluster's subnet; link private DNS zones to its VNet.",
    "assignableScopes": ["<virtual-network-resource-id>"],
    "permissions": [
      {
        "actions": [
          "Microsoft.Network/virtualNetworks/join/action",
          "Microsoft.Network/virtualNetworks/subnets/read",
          "Microsoft.Network/virtualNetworks/subnets/join/action",
          "Microsoft.Network/virtualNetworks/checkIpAddressAvailability/read"
        ],
        "notActions": [],
        "dataActions": [],
        "notDataActions": []
      }
    ]
  }
}
```

Why: the wrapper reads the subnet to validate its service endpoints; creating
NICs inside the subnet requires `subnets/join/action`; linking privatelink DNS
zones to the VNet requires `virtualNetworks/join/action`. The
`checkIpAddressAvailability/read` entry deserves a note: floating-IP
allocation probes candidate addresses with the CheckIPAddressAvailability API,
and when the caller lacks this right, Azure returns an empty **200** response
rather than a 403 -- the provider reads that as "no free addresses in the
subnet," a misleading failure that looks like subnet exhaustion. Grant it and
the probe returns real availability.

```json
{
  "properties": {
    "roleName": "Qumulo CNQ Subnet Join (<resource-group>)",
    "description": "Join the CNQ cluster's subnet.",
    "assignableScopes": ["<virtual-network-resource-id>"],
    "permissions": [
      {
        "actions": ["Microsoft.Network/virtualNetworks/subnets/join/action"],
        "notActions": [],
        "dataActions": [],
        "notDataActions": []
      }
    ]
  }
}
```

Why a second, one-action role: the node identity attaches floating IPs as
secondary IP configurations in the cluster subnet at runtime, and that is the
only network right it needs at the VNet. Keeping it separate from the
deployer's network role keeps the runtime identity's grant as small as it can
be.

## Step 6: Custom role "Qumulo CNQ Cluster Node" (resource group)

Portal: the deployment resource group → **IAM → Add custom role → JSON tab**.

```json
{
  "properties": {
    "roleName": "Qumulo CNQ Cluster Node (<resource-group>)",
    "description": "Qumulo Core's floating-IP management on cluster node NICs.",
    "assignableScopes": [
      "/subscriptions/<subscription-id>/resourceGroups/<resource-group>"
    ],
    "permissions": [
      {
        "actions": [
          "Microsoft.Network/networkInterfaces/read",
          "Microsoft.Network/networkInterfaces/write",
          "Microsoft.Network/applicationSecurityGroups/joinIpConfiguration/action",
          "Microsoft.Network/networkSecurityGroups/join/action"
        ],
        "notActions": [],
        "dataActions": [],
        "notDataActions": []
      }
    ]
  }
}
```

Why: Qumulo Core's floating-IP reconciler runs on the cluster under the node
identity. It lists the resource group's NICs and rewrites node NIC IP
configurations; because those configurations reference the NIC's application
security groups and network security group, the two join actions are required
for the write to be accepted. These four actions replace the Virtual Machine
Contributor and Network Contributor grants the provider would otherwise assign
-- a large reduction for the identity that runs on the cluster itself.

## Step 7: Role assignments

Portal, at each scope: **Access control (IAM) → Add → Add role assignment**;
pick the role, then **Members → Managed identity** (for the identities) or
**User/Group/Service principal** (for the deployer).

| Principal | Role | Scope | Why |
|---|---|---|---|
| deployer | Qumulo CNQ Deployer | deployment resource group | everything in step 3 |
| deployer | Qumulo CNQ Deployer Subscription | subscription | everything in step 4 |
| deployer | Qumulo CNQ Deployer Network | virtual network | subnet read/join, DNS links, IP availability |
| node identity | Qumulo CNQ Cluster Node | deployment resource group | floating-IP management |
| node identity | Qumulo CNQ Subnet Join | virtual network | floating IPs join the subnet |
| node identity | Key Vault Secrets User (built-in) | deployment resource group | Qumulo Core reads the SAS definitions the provider stored in the vault |
| node identity | Storage Blob Data Reader (built-in) | deployment resource group | reads deployment assets from blob storage |
| provisioner identity | App Configuration Data Owner (built-in) | deployment resource group | writes provisioning status keys the provider and operators poll |
| deployer | Reader (built-in) | the Azure SSH key named by `ssh_public_key_id`, when set | reads the node public key at plan time, wherever the key lives |
| provisioner identity | Reader (built-in) | deployment resource group | resolves the resources it reports against |
| provisioner identity | Key Vault Secrets User (built-in) | deployment resource group | matches the grant the provider makes for its own provisioner identities |

The built-in grants use resource-group scope because the vault, storage
accounts, and App Configuration store do not exist until the first deploy, so
they cannot be granted per-resource in advance.

## Step 8: Operator (human) read-only access

The deployer principal is deliberately narrow, so the people running a deploy
cannot watch it with their own accounts unless you grant them read access.
For each operator, assign at the deployment resource group:

| Role (built-in) | What it gives the operator |
|---|---|
| Reader | see the deployment's resources |
| App Configuration Data Reader | the provisioner's status keys, e.g. `az appconfig kv show --endpoint https://<deployment>-deployment.azconfig.io --auth-mode login --key last-run-status` |
| Log Analytics Reader | the provisioner log, via `tools/get-provisioner-log.sh` |

Deploy as the locked-down principal; watch and troubleshoot as yourself.

Include the administrator who performs this setup: the status keys are an App
Configuration **data**-plane read, and Azure management rights -- even Owner's
`*` -- carry no data actions, so an admin without App Configuration Data
Reader cannot read them either. (The Terraform in this directory adds its own
executor automatically; in the Portal, add yourself here.)

## Optional grants

- **Customer-managed Key Vault** (`key_vault_id`): the deployer reads the
  vault and stores SAS definitions in it; the nodes and provisioner read
  secrets from it. On a vault with the **RBAC permission model**, assign the
  deployer **Key Vault Administrator** on the vault and scope the node and
  provisioner **Key Vault Secrets User** assignments to the vault instead of
  the resource group. On a vault that uses **access policies**, assign the
  deployer **Reader** on the vault (the management-plane read) and add access
  policies: deployer -- secrets Get/List/Set/Delete and storage
  Get/List/Set/Delete/GetSAS/ListSAS/SetSAS/DeleteSAS; node and provisioner
  identities -- secrets Get/List.
- **Admin password in Key Vault** (`admin_pwd_or_keyvault_secret_id` as a
  secret reference): the deployer reads that secret at apply time, so grant it
  **Key Vault Secrets User** on the secret (RBAC vault) or a secrets **Get**
  access policy (policy vault) -- on whichever vault holds the password, which
  is often not the deployment's vault.
- **Separate persistent-storage resource group**: only storage accounts, the
  Key Vault, and (with deletion protection) their locks land there. Create a
  reduced copy of the step 3 role containing just the
  `Microsoft.Resources/subscriptions/resourceGroups/read`, `Microsoft.Storage`,
  and `Microsoft.KeyVault` blocks (actions and data actions), and assign it
  there; also move the node identity's Storage Blob Data Reader to that group.
- **Custom VM images** (wrapper `custom_image_id` / `provisioner_custom_image_id`):
  creating a VM from an image the deployer cannot read fails
  (`LinkedAuthorizationFailed` on `galleries/images/versions/read`), so assign
  the deployer **Reader** on the image -- for a Compute Gallery image, on the
  gallery itself, so a refreshed image definition or version deploys without a
  new grant. The gallery may live in another resource group or subscription;
  the assignment goes wherever the image is.
- **Private DNS zones** (wrapper `private_link_*_dns_zone_id`): assign the
  deployer **Private DNS Zone Contributor** on each zone.
- **AzureAD-authenticated Terraform state**: assign the deployer **Storage
  Blob Data Contributor** on the state storage account.
- **Deletion protection**: add the lock actions to the step 3 role (and the
  persistent-storage role if used), as noted in each step.

## Wire it into the wrapper

```hcl
resource_group_name      = "<resource-group>"
subnet_id                = "<subnet-resource-id>"
cluster_node_identity_id = "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<rg>-node"
provisioner_identity_id  = "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<rg>-provisioner"
```

Run `terraform` as the deployer principal. If the deployer is a managed
identity on a runner VM with several identities, pin it with
`ARM_CLIENT_ID` / `AZURE_CLIENT_ID`.

## Hint: runner VMs with auto-attached managed identities

A common trap when the terraform runner is a VM inside the VNet (usual for
private-endpoint deployments): many organizations attach a user-assigned
managed identity to every VM by policy. The qumulo provider authenticates with
Azure's default credential chain, which tries a managed identity **before**
the Azure CLI login -- so terraform silently runs as the auto-attached
identity, not as the user who ran `az login`, and fails with
`AuthorizationFailed` errors naming a principal nobody recognizes. The azurerm
provider has its own CLI-first chain, so the same apply can even authenticate
as two different principals, one per provider, which makes the errors harder
to read.

Fixes, by intent:

- **Deploy as the logged-in CLI user**: set `AZURE_TOKEN_CREDENTIALS` to
  `AzureCLICredential` (PowerShell:
  `$env:AZURE_TOKEN_CREDENTIALS="AzureCLICredential"`). This restricts the
  default chain to the CLI credential only.
- **Deploy as a specific managed identity on the VM** (the deployer identity
  from this setup): set `AZURE_CLIENT_ID` to that identity's client ID for the
  qumulo provider, and `ARM_CLIENT_ID` (with `ARM_USE_MSI=true`) for azurerm.

Either way, set the variables in the same shell that runs terraform, and keep
both providers pointed at the same principal -- the grants in this document
assume one deployer.
