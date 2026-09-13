#Apply-side visibility for boot hooks. A provider cannot stream text into the apply UI,
#but a local-exec provisioner can, and a resource with no dependency on the cluster runs
#concurrently with it: this terraform_data tails the deployment VMs' boot-diagnostics
#serial logs and prints every wired hook's "[<hook_name>] ..." lines into the
#`terraform apply` output. Enabled whenever a pre_run/post_run hook is wired
#(hooks_apply_watch = false opts out). It is replaced on every apply, so a retry after a
#failed create is watched too; the VM count taken at plan time lets the script exit at
#once when every node already exists (a no-op apply, or an update that boots no VM).
#The script always exits 0 -- the watch can never fail a deploy.

# The watch scripts exist as bash (Linux, macOS) and PowerShell (Windows) editions.
# hooks_watch_shell picks one; null detects Windows by its system directory, which no
# other platform has, and otherwise uses bash.
locals {
  hook_watch_shell = coalesce(var.hooks_watch_shell, fileexists("C:/Windows/System32/cmd.exe") ? "powershell" : "bash")
  hook_watch_programs = {
    bash       = { count = ["bash", "${path.module}/tools/hooks/count-vms.sh"], interpreter = ["bash"], script = "${path.module}/tools/hooks/apply-hook-watch.sh" }
    pwsh       = { count = ["pwsh", "-NoProfile", "-NonInteractive", "-File", "${path.module}/tools/hooks/count-vms.ps1"], interpreter = ["pwsh", "-NoProfile", "-NonInteractive", "-File"], script = "${path.module}/tools/hooks/apply-hook-watch.ps1" }
    powershell = { count = ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", "${path.module}/tools/hooks/count-vms.ps1"], interpreter = ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"], script = "${path.module}/tools/hooks/apply-hook-watch.ps1" }
  }
  hook_watch_count_program = local.hook_watch_programs[local.hook_watch_shell].count
  hook_watch_interpreter   = local.hook_watch_programs[local.hook_watch_shell].interpreter
  hook_watch_script        = local.hook_watch_programs[local.hook_watch_shell].script
}

data "external" "deployment_vms" {
  count = var.hooks_apply_watch && length(local.hook_watch_tags) > 0 ? 1 : 0

  program = local.hook_watch_count_program
  query   = { resource_group = local.resource_group_unique_name }
}

resource "terraform_data" "hook_watch" {
  count = var.hooks_apply_watch && length(local.hook_watch_tags) > 0 ? 1 : 0

  triggers_replace = [plantimestamp()]

  provisioner "local-exec" {
    interpreter = local.hook_watch_interpreter
    command     = local.hook_watch_script
    environment = {
      WATCH_RG           = local.resource_group_unique_name
      WATCH_TAGS         = join("|", local.hook_watch_tags)
      WATCH_NODE_COUNT   = var.node_count
      WATCH_EXISTING_VMS = data.external.deployment_vms[0].result.count
      WATCH_MAX_SECONDS  = 60 * (coalesce(var.provider_create_timeout_minutes, var.provider_timeout_minutes) + 5)
    }
  }
}
