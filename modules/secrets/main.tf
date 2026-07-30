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
  # 1. Check if the input is a Key Vault secret resource ID
  is_keyvault_ref = can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+/secrets/[^/]+$", var.admin_pwd_or_keyvault_secret_id))

  # 2. Split the reference into the vault's resource ID and the secret name
  keyvault_ref_parts = local.is_keyvault_ref ? regex(
    "^(?P<key_vault_id>/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+)/secrets/(?P<secret_name>[^/]+)$",
    var.admin_pwd_or_keyvault_secret_id
  ) : null

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

# Only fetches from Azure Key Vault if the single input was detected as a secret resource ID
data "azurerm_key_vault_secret" "selected" {
  count        = local.is_keyvault_ref ? 1 : 0
  name         = local.keyvault_ref_parts.secret_name
  key_vault_id = local.keyvault_ref_parts.key_vault_id
}
