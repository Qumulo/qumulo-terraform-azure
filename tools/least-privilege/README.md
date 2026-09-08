# Least-privilege roles and identities for CNQ Azure deployments

Standalone Terraform that creates the minimum Azure roles and identities a CNQ
deployment needs. Run it once as a privileged administrator (creating role
definitions and assignments requires Owner or User Access Administrator on the
scopes involved). The deployment itself then runs under the narrow grants
created here instead of Owner or Contributor + User Access Administrator.

This configuration is independent of the wrapper: it has its own state, and its
outputs feed the wrapper's inputs.

## What it creates

| Object | Scope | Held by |
|---|---|---|
| Resource group (optional) | -- | the deployment |
| Custom role `Qumulo CNQ Deployer` | deployment resource group | deployer principal |
| Custom role `Qumulo CNQ Deployer Subscription` | subscription (reads + soft-delete purge) | deployer principal |
| Custom role `Qumulo CNQ Deployer Network` | cluster virtual network | deployer principal |
| Custom role `Qumulo CNQ Deployer Storage` (optional) | persistent-storage resource group | deployer principal |
| Custom role `Qumulo CNQ Subnet Join` | cluster virtual network | node identity |
| Custom role `Qumulo CNQ Cluster Node` | deployment resource group | node identity |
| User-assigned identity `<rg>-node` + grants | resource group | cluster node VMs |
| User-assigned identity `<rg>-provisioner` + grants | resource group | provisioner VM |
| User-assigned identity `<rg>-deployer` (optional) | resource group | terraform runner VM |

The node and provisioner identity outputs plug into the wrapper's
`cluster_node_identity_id` and `provisioner_identity_id`. Supplying both makes
the qumulo provider skip all of its own role management: no subscription-scope
subnet-join custom role, no built-in-role assignments to VM identities, and no
permission preflight. The `wrapper_tfvars` output lists exactly what to set.

## Usage

The shared deployment values -- subscription, subnet, resource group, location,
tags, `key_vault_id`, `deletion_protection`, `persistent_storage_resource_group`,
and the `*_private_dns_zone_id` zones -- are inherited from the wrapper's
top-level `terraform.tfvars`: this module declares the same variable names, so
one file supplies both configurations. Fill in this directory's
`terraform.tfvars` with what the wrapper does not know (the deployer principal
and any extra operators), then run with both files, later file winning:

```
terraform init
terraform apply -var-file=../../terraform.tfvars -var-file=terraform.tfvars
```

Terraform warns about the wrapper file's variables this module does not declare
("Value for undeclared variable"); the warnings are expected and harmless. To
override an inherited value, set it in this directory's file -- the second
`-var-file` wins.

Then copy the `wrapper_tfvars` output into the wrapper's configuration. To run
terraform from a VM instead of as a person, set `create_deployer_identity =
true` and attach the `deployer_identity` output to the runner VM (pin it with
`ARM_CLIENT_ID` / `AZURE_CLIENT_ID` if the VM has several identities).

## Operators: watching and troubleshooting a deployment

The deployment principal is deliberately narrow, so the humans running a
deploy cannot see its progress with their own accounts. The identity that runs
this Terraform gets read-only operator access automatically (disable with
`grant_executor_operator_access = false`, e.g. for a pipeline principal); list
any additional operators' object IDs in `operator_principal_ids`. Each
operator gets, at the deployment resource group: Reader (see the resources),
App Configuration Data Reader (the provisioner's status keys, e.g.
`az appconfig kv show --endpoint
https://<deployment>-deployment.azconfig.io --auth-mode login --key
last-run-status`), and Log Analytics Reader (the provisioner log via
`tools/get-provisioner-log.sh`). Deploy as the locked-down principal; watch
and troubleshoot as yourself. The App Configuration grant matters even for
administrators: the status keys are a data-plane read, which no management
role -- Owner included -- carries.

## Why each grant exists

Every right, its consumer, and an Azure Portal walkthrough for creating the
same setup by hand live in [PERMISSIONS.md](PERMISSIONS.md). The grants were
derived from what the qumulo provider, the wrapper, and Qumulo Core actually
call -- not from prior documentation -- and verified by live deployments
(create, scale, replace, destroy) running under exactly these permissions.

## Out of scope: provider-managed identities

Deploying without `cluster_node_identity_id` and `provisioner_identity_id`
makes the provider create system-assigned identities and assign roles itself,
including a per-deployment custom role at subscription scope. That path
requires the deployer to hold `Microsoft.Authorization/roleDefinitions` and
`roleAssignments` write at subscription scope -- it is role administration by
the deployment, not a least-privilege model, and this module does not support
it. Always pass both identity outputs to the wrapper.

## Known limits

- Provider releases through 1.4.13 have a defect in the pre-created-identity
  path ([provider #790](https://github.com/Qumulo/terraform-provider-qumulo-cloud/issues/790),
  fix in [#795](https://github.com/Qumulo/terraform-provider-qumulo-cloud/pull/795)):
  the provisioner logs in with the wrong identity and every operation fails.
  Until a release carries the fix, pass the SAME identity for both
  `cluster_node_identity_id` and `provisioner_identity_id` and give it the
  union of both identities' grants.
- Destroy on current provider releases fails at its final step trying to
  delete a role this deployment mode never creates
  ([provider #791](https://github.com/Qumulo/terraform-provider-qumulo-cloud/issues/791));
  all deployment resources are removed first. Do not simply re-run destroy
  ([provider #792](https://github.com/Qumulo/terraform-provider-qumulo-cloud/issues/792));
  verify the resource group is empty, then remove the resource from state.
- Scale-up, node replacement, and destroy run under the same grants; destroy
  of the resource group itself is not granted (this module owns the group).
- The optional search appliance and threat-detection features are not covered;
  they additionally need `Microsoft.Compute/virtualMachines/runCommand/action`
  and, for threat detection, AAD SSH extension and a dedicated vault.
- Custom role names are tenant-unique; `name_suffix` (default: the resource
  group name) keeps parallel deployments from colliding.
