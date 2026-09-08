variable "targets" {
  description = "The resources to disable public network access on: full ARM resource ID plus the ARM type@api-version to address it with. Values may be unknown at plan time (they come from the cluster's endpoint outputs); target_count carries the plan-time-known length."
  type = list(object({
    resource_id = string
    type        = string
  }))
}

variable "target_count" {
  description = "Plan-time-known number of entries in targets. Required because count must be known at plan while the target values are computed during the apply."
  type        = number
  nullable    = false
}
