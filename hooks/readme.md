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
