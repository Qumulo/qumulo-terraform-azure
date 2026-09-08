## NOTE:
Place pre-run or post-run files here.  The hook for pre/post run files points to this directory.

## WARNING:
You may also place entire boot script override files here.  Customizing the boot script comes with significant risk.  We recommend you collaborate with your Qumulo SE if you need to customize the boot script for an instance deployed by the Qumulo Provider.  In most cases pre-run or post-run additions will provide the necessary customization.

## Hook contract

Hooks are not standalone scripts: each pre/post hook file is inlined verbatim
into a single `bash -xe -o pipefail` boot script per VM role. Every hook in a
chain must therefore be **bash**, and the chain must remain valid when merged:

- No shebang line and no top-level `exit` -- either would belong to the whole
  boot script, not the hook. (`override_file` is the exception: it replaces the
  entire script and should be a complete standalone script.)
- Anything that may fail runs in a condition context (`if`, `while`, `|| true`)
  so `-e` cannot abort the boot.
- Namespace functions and any non-`local` variables with the hook's own name
  (`wait_for_<hook>...`): chained hooks share one shell.
- Log progress as `[<hook_name>] message`, where `hook_name` is the file name
  without `.sh` and with dashes as underscores (`wait-for-x.sh` logs
  `[wait_for_x]`), and write it to both stdout and `/dev/console` so boot
  diagnostics captures it. A waiting hook logs at least once a minute. While a
  `terraform apply` boots VMs with hooks wired, the wrapper tails those lines
  from every VM's boot-diagnostics serial log into the apply output
  (hooks-watch.tf, needs the az CLI; `hooks_apply_watch = false` opts out).
  Outside an apply, `tools/hooks/watch-hooks.sh [<resource-group>]` shows the
  same lines.

Terraform enforces the cheap parts at plan time (`.sh` suffix, no shebang).
Check the rest -- including that the merged chain parses -- with:

```
tools/validate-hooks.sh <hook-file> [<hook-file> ...]
```

## Chaining hooks

`node_hooks_files` and `provisioner_hooks_files` accept `pre_run_files` /
`post_run_files` lists (the singular `pre_run_file` / `post_run_file` remain
for one hook). Listed files are inlined into the boot script in order, each
under a banner naming its file. For example, a locked-down RHEL BYOS
environment chains, in order: wait for the platform's own provisioning to
finish, wait for private-endpoint DNS, then wait for the subscription
entitlement (the wait-for-* hooks named here ship separately):

```hcl
provisioner_hooks_files = {
  pre_run_files = [
    "wait-for-provisioning-complete.sh",
    "wait-for-private-endpoints.sh",
    "wait-for-rhel-entitlement.sh",
  ]
}
node_hooks_files = {
  pre_run_files = [
    "wait-for-provisioning-complete.sh",
    "wait-for-rhel-entitlement.sh",
  ]
}
```
## Included hooks

### wait-for-provisioning-complete.sh (node or provisioner pre_run)

For environments where separate platform automation finishes preparing each VM
after boot: waits until a marker file exists on the VM's local disk. The path is
the one setting at the top of the hook, `/tmp/provisioning-complete` by default;
change it there, or assign `provisioning_complete_file` in an earlier chained
hook. The platform automation creates the file (`touch
/tmp/provisioning-complete` is enough) as its final step. No timeout of its own; the provider timeout of the running
operation is the backstop (see Timeouts below).
Logs to the serial console as `[wait_for_provisioning_complete]`.

### wait-for-rhel-entitlement.sh (node pre_run)

For RHEL BYOS images -- for example Red Hat gold images -- that boot before
their subscription entitlement is active. Package installation fails until Red
Hat content is reachable, so this hook blocks the node boot script until `dnf`
sees RHEL repositories and can refresh its cache. It never gives up on its
own; the provider timeout of the running operation bounds the wait (see
Timeouts below). Marketplace PAYG images include RHUI and do not need it.

Enable it for the cluster nodes:

```hcl
node_hooks_files = {
  pre_run_file = "wait-for-rhel-entitlement.sh"
}
```

The hook logs every poll to the VM serial console as
`[wait_for_rhel_entitlement] ...`; the apply-side hook watch (see "Hook
contract") shows the wait in the `terraform apply` output.

### Timeouts

These hooks wait inside every operation that boots a VM: the initial create,
node replacement (a `vm_type`, zone, or image change), scale-out, and the
provisioner VM of a scale-in. The provider's timeout for that operation is the
only bound on the wait, so size `provider_timeout_minutes` (or each
`provider_*_timeout_minutes`) for the platform's worst case -- not only the
create timeout. With the 30-minute default, a node replacement whose new nodes
each waited about five minutes ran out of time during the provider's final
read, and Terraform reported the apply as failed although the replacement had
completed.
