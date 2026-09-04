#Pre-deployment refusal when the deployment resource group contains NICs the
#cluster's floating-IP reconcile would damage. Qumulo Core's reconcile removes
#every secondary IP on every VM-attached primary NIC in the cluster's resource
#group that it did not assign itself (QSTON-1676) -- any neighboring VM loses
#its secondary addresses on every reconcile pass, floating IPs configured or
#not. Releases from fip_scoped_reconcile_version onward manage only NICs
#carrying the cluster's own qumulo-deployment tag, so sharing becomes safe.
#This check runs at plan, before anything is created.

locals {
  #The first Qumulo Core release whose reconcile is scoped by the
  #qumulo-deployment NIC tag. PLACEHOLDER until the fix ships in a release.
  fip_scoped_reconcile_version = "7.10.1"

  #Dotted versions as fixed-width strings so string comparison orders them
  #numerically ("7.10.1" > "7.9.2").
  fip_fix_version_key = join(".", [
    for part in slice(concat(split(".", local.fip_scoped_reconcile_version), ["0", "0"]), 0, 3) :
    format("%05d", try(tonumber(part), 0))
  ])
  cluster_version_key = var.cluster_version == null ? null : join(".", [
    for part in slice(concat(split(".", var.cluster_version), ["0", "0"]), 0, 3) :
    format("%05d", try(tonumber(part), 0))
  ])

  #cluster_version = null installs the latest release; treat it as carrying
  #the fix once fip_scoped_reconcile_version has shipped.
  cluster_version_has_scoped_reconcile = (
    var.cluster_version == null || local.cluster_version_key > local.fip_fix_version_key
  )

  #NICs the reconcile would strip: attached to a VM, holding secondary
  #addresses, and not this deployment's own (the provider tags its NICs
  #qumulo-deployment = "<deployment_name>-<suffix>").
  vulnerable_rg_nics = [
    for nic in data.azurerm_network_interface.deployment_resource_group :
    nic.name
    if nic.virtual_machine_id != null
    && nic.virtual_machine_id != ""
    && length(nic.private_ip_addresses) > 1
    && !startswith(lookup(nic.tags == null ? {} : nic.tags, "qumulo-deployment", ""), "${var.deployment_name}-")
  ]
}

#Subscription-wide on purpose: listing by resource_group_name returns a 404
#when the group does not exist yet, which is every first apply. A missing
#group filters down to zero NICs, which is also the right answer -- a group
#the provider is about to create is empty.
data "azurerm_resources" "subscription_nics" {
  type = "Microsoft.Network/networkInterfaces"
}

data "azurerm_network_interface" "deployment_resource_group" {
  for_each = toset([
    for resource in data.azurerm_resources.subscription_nics.resources :
    resource.name
    if lower(split("/", resource.id)[4]) == lower(local.resource_group_unique_name)
  ])

  name                = each.key
  resource_group_name = local.resource_group_unique_name
}
