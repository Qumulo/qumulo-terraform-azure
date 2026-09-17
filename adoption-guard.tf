# Adoption guard: an advisory comparison of the configuration against the node
# VMs already in the resource group. On an imported cluster the provider rebuilds
# every node when vm_type or availability_zones differ from the live fleet, and
# scales it when node_count differs, while the plan shows only an in-place
# change. A check block can warn but never stop an apply, so read the warning.

data "azapi_resource_list" "node_vms" {
  count                  = var.adoption_guard ? 1 : 0
  type                   = "Microsoft.Compute/virtualMachines@2024-07-01"
  parent_id              = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${var.resource_group_name}"
  response_export_values = ["value"]
}

locals {
  live_nodes = var.adoption_guard ? [
    for vm in try(data.azapi_resource_list.node_vms[0].output.value, []) : vm if can(regex("-node-[0-9]+$", vm.name))
  ] : []
  live_sizes = distinct([for vm in local.live_nodes : try(vm.properties.hardwareProfile.vmSize, "")])
  live_zones = sort(distinct(flatten([for vm in local.live_nodes : try(vm.zones, [])])))
  live_matches_config = (
    length(local.live_nodes) == var.node_count &&
    length(local.live_sizes) == 1 && local.live_sizes[0] == var.vm_type &&
    join(",", local.live_zones) == join(",", try(sort(var.availability_zones), []))
  )
}

check "adoption_guard_live_fleet" {
  assert {
    condition     = !var.adoption_guard || length(local.live_nodes) == 0 || local.live_matches_config
    error_message = "The configuration disagrees with the node VMs in resource group '${var.resource_group_name}': live fleet has ${length(local.live_nodes)} node(s) of size ${join(",", local.live_sizes)} in zone(s) [${join(",", local.live_zones)}]; configuration says node_count=${var.node_count}, vm_type=${var.vm_type}, availability_zones=[${join(",", try(sort(var.availability_zones), []))}]. Applying rebuilds every node (size or zones) or scales the cluster (count). Pin the configuration to the live values before applying, or set adoption_guard = false to silence this."
  }
}
