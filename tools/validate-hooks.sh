#!/usr/bin/env bash
# Validate that a chain of hook files merges into one valid bash fragment.
#
# Hooks are inlined, in order, into a single bash -xe -o pipefail boot script
# (see hooks/readme.md for the contract). This checks what Terraform cannot:
#   - each file is bash without a shebang and without a top-level exit
#   - no two files define the same function
#   - the concatenation parses (bash -n)
#
# Usage: tools/validate-hooks.sh <hook-file> [<hook-file> ...]
#   File names are relative to the hooks/ directory (matching the
#   node_hooks_files / provisioner_hooks_files values), or paths.
#
# Example (a provisioner chain):
#   tools/validate-hooks.sh wait-for-provisioning-complete.sh \
#     wait-for-private-endpoints.sh wait-for-rhel-entitlement.sh

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <hook-file> [<hook-file> ...]" >&2
  exit 2
fi

hooks_dir="$(cd "$(dirname "$0")/../hooks" && pwd)"
fail=0

resolve() {
  if [ -f "$1" ]; then
    echo "$1"
  elif [ -f "$hooks_dir/$1" ]; then
    echo "$hooks_dir/$1"
  else
    echo "ERROR: hook file not found: $1 (looked in . and $hooks_dir)" >&2
    return 1
  fi
}

files=()
for arg in "$@"; do
  files+=("$(resolve "$arg")") || exit 2
done

for f in "${files[@]}"; do
  head -c 2 "$f" | grep -q '^#!' && { echo "FAIL: $f starts with a shebang; hooks are inlined mid-script" >&2; fail=1; }
  grep -nE '^exit\b' "$f" && { echo "FAIL: $f has a top-level exit; it would end the whole boot script" >&2; fail=1; }
  bash -n "$f" || { echo "FAIL: $f does not parse alone" >&2; fail=1; }
done

# Function names defined by more than one file collide when merged.
dupes=$(for f in "${files[@]}"; do
  grep -oE '^\s*[A-Za-z_][A-Za-z0-9_]*\(\)' "$f" | tr -d ' ()' | sort -u | sed "s|^|$(basename "$f") |"
done | awk '{print $2}' | sort | uniq -d)
if [ -n "$dupes" ]; then
  echo "FAIL: function name(s) defined by more than one hook: $dupes" >&2
  fail=1
fi

if ! cat "${files[@]}" | bash -n; then
  echo "FAIL: the merged chain does not parse" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "OK: ${#files[@]} hook(s) merge into a valid bash fragment"
fi
exit "$fail"
