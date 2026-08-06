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
  # This is the form shown in the Azure Portal and by `az keyvault secret show`.
  is_uri_ref = can(regex("^https://[a-zA-Z0-9-]+\\.vault\\.(azure\\.net|usgovcloudapi\\.net)/secrets/[a-zA-Z0-9-]+(/[a-zA-Z0-9]+)?/?$", var.admin_pwd_or_keyvault_secret_id))

  is_keyvault_ref = local.is_arm_ref || local.is_uri_ref

  # 2a. Split an ARM reference into the vault's resource ID and the secret name
  arm_ref_parts = local.is_arm_ref ? regex(
    "^(?P<key_vault_id>/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+)/secrets/(?P<secret_name>[^/]+)$",
    var.admin_pwd_or_keyvault_secret_id
  ) : null

  # 2b. Split a URI reference into the vault name and the secret name
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

# Only fetches from Azure Key Vault if the single input was detected as a secret reference
data "azurerm_key_vault_secret" "selected" {
  count        = local.is_keyvault_ref ? 1 : 0
  name         = local.keyvault_secret_name
  key_vault_id = local.keyvault_id
}
