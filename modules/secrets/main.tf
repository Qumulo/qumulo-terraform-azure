#MIT License

#Copyright (c) 2026 Qumulo, Inc.

#Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the Software), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

locals {
  # 1a. Check if the input is a Key Vault secret ARM resource ID
  is_arm_ref = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+/secrets/[^/]+$", var.admin_pwd_or_keyvault_secret_id))

  # 1b. Check if the input is a Key Vault secret URI, e.g. https://<vault>.vault.azure.net/secrets/<name>/<version>
  # This is the form shown in the Azure Portal and by `az keyvault secret show`. The trailing
  # /<version> segment is OPTIONAL and accepted here purely so a URI copy-pasted straight from
  # the Portal (which always includes a version) parses successfully -- see the note below on why
  # it is never used to pin a specific version.
  is_uri_ref = can(regex("^https://[a-zA-Z0-9-]+\\.vault\\.(azure\\.net|usgovcloudapi\\.net)/secrets/[a-zA-Z0-9-]+(/[a-zA-Z0-9]+)?/?$", var.admin_pwd_or_keyvault_secret_id))

  is_keyvault_ref = local.is_arm_ref || local.is_uri_ref

  # 2a. Split an ARM reference into the vault's resource ID and the secret name
  arm_ref_parts = local.is_arm_ref ? regex(
    "^(?P<key_vault_id>/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+)/secrets/(?P<secret_name>[^/]+)$",
    var.admin_pwd_or_keyvault_secret_id
  ) : null

  # 2b. Split a URI reference into the vault name and the secret name. Any version segment present
  # in the URI is matched here (so the regex above still accepts it) but deliberately discarded --
  # see the data source below for why this always resolves to Key Vault's CURRENT/LATEST version,
  # never a pinned one, regardless of what version (if any) the URI names.
  uri_ref_parts = local.is_uri_ref ? regex(
    "^https://(?P<vault_name>[a-zA-Z0-9-]+)\\.vault\\.(?:azure\\.net|usgovcloudapi\\.net)/secrets/(?P<secret_name>[a-zA-Z0-9-]+)(?:/[a-zA-Z0-9]+)?/?$",
    var.admin_pwd_or_keyvault_secret_id
  ) : null

  keyvault_secret_name = local.is_arm_ref ? local.arm_ref_parts.secret_name : (local.is_uri_ref ? local.uri_ref_parts.secret_name : null)

  # A URI reference only gives us the vault's DNS name, so resolve it to a resource ID by
  # searching for a Key Vault with that name in the subscription (Key Vault names are globally unique).
  keyvault_id = local.is_arm_ref ? local.arm_ref_parts.key_vault_id : (local.is_uri_ref ? data.azurerm_resources.by_vault_name[0].resources[0].id : null)

  # 3. Extract the raw string from Key Vault if a reference was provided
  raw_keyvault_secret = local.is_keyvault_ref ? data.azurerm_key_vault_secret.selected[0].value : null

  # 4. Safely parse the secret
  # - try() attempts the first argument: treating it as JSON and looking for ANY case variation of "password" key.
  # - If that fails (e.g., it's a plain text secret, or "password" key doesn't exist), it uses the raw string.
  parsed_keyvault_secret = local.is_keyvault_ref ? try(
    [for k, v in jsondecode(local.raw_keyvault_secret) : v if lower(k) == "password"][0],
    local.raw_keyvault_secret
  ) : null

  # 5. Route the final password dynamically
  final_password = local.is_keyvault_ref ? local.parsed_keyvault_secret : var.admin_pwd_or_keyvault_secret_id
}

# Resolves a Key Vault URI reference's vault name to its resource ID
data "azurerm_resources" "by_vault_name" {
  count = local.is_uri_ref ? 1 : 0
  type  = "Microsoft.KeyVault/vaults"
  name  = local.uri_ref_parts.vault_name
}

# Only fetches from Azure Key Vault if the single input was detected as a secret reference.
#
# IMPORTANT: `version` is intentionally left unset, so this ALWAYS reads the secret's current/
# latest enabled version at plan/apply time -- even if the admin_pwd_or_keyvault_secret_id URI you
# supplied includes an older version segment (e.g. copied straight from the Azure Portal or from
# `az keyvault secret show`, which always shows a specific version). That version segment is
# accepted for convenience but is otherwise ignored; it is never used to pin a fetch to an older
# value. If you rotate the secret in Key Vault, the next Terraform run picks up the new value.
#
# Also note: admin_password on the underlying cluster resource is write-only, so Terraform never
# stores its value in state -- but its currently-resolved value IS supplied to the provider on
# EVERY apply that touches this resource, not just at creation. Node/vm_type changes (scaling,
# replacement, etc.) require the provider to authenticate to the existing cluster using this value,
# so it must keep matching the cluster's actual current admin password for those operations to
# succeed (see the WARNING below). What it does NOT do is rotate the password: supplying a new
# value here does not itself change an already-running cluster's password. If you change the
# password via the Qumulo UI or qumulo-cli, update the Key Vault secret to match (or vice versa) so
# future applies keep authenticating successfully.
#
# WARNING -- known failure mode on an EXISTING cluster: if the value resolved here no longer
# matches the cluster's actual current admin password (because the two drifted out of sync per the
# note above), an apply that needs to authenticate to the running cluster -- e.g. scaling
# node_count, changing vm_type, or anything else that touches existing nodes -- can fail partway
# through, after Azure resources have already started being created/modified. Terraform does not
# automatically roll back or clean up in that situation; you may be left with partially-provisioned
# resources requiring manual cleanup. There is no pre-flight check here that verifies this password
# against the live cluster before changes begin (doing so safely would require calling the
# cluster's REST API login endpoint, which cannot be done from a plain Terraform data source without
# writing the plaintext password into the state file -- confirmed by testing, not just assumed).
# Before applying any change to an EXISTING cluster, verify the resolved password still matches
# what the cluster actually has configured.
data "azurerm_key_vault_secret" "selected" {
  count        = local.is_keyvault_ref ? 1 : 0
  name         = local.keyvault_secret_name
  key_vault_id = local.keyvault_id
}
