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

# If you have configured credentials for the Azure CLI, they should get picked up
# automatically. You can also authenticate with:
# - Environment variables: ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
# - Managed Identity (when running from an Azure VM/DevOps agent with one assigned)
# More information can be found here:
#   https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs

provider "azurerm" {
  features {}

  subscription_id = var.azure_subscription_id
}

# Aliased provider for private DNS zone record writes. Zones commonly live in a
# hub subscription; the subscription is parsed from the supplied zone resource
# IDs (see private-link.tf). With no zones supplied this collapses to the same
# configuration as the default azurerm provider.
provider "azurerm" {
  alias = "dns"
  features {}

  subscription_id = local.dns_zone_subscription_id != null ? local.dns_zone_subscription_id : var.azure_subscription_id
}

# azapi performs the post-deployment public-network-access PATCHes on resources
# the qumulo provider created (azurerm cannot manage resources it did not
# create). Same default ARM credential chain; resources are addressed by
# absolute ID, so no subscription pin is needed.
provider "azapi" {}

provider "qumulo" {
  # OPTIONAL: auto-mints the deprecated per-cluster nexus_registration_key and onboards new
  # clusters to Nexus Fleet automatically. Leave both null to skip Nexus onboarding entirely.
  nexus_api_token  = var.nexus_api_token
  nexus_account_id = var.nexus_account_id

  azure {
    # Standard Azure credential chain applies (env vars, Azure CLI, managed
    # identity). No explicit credentials are required here.
    subscription_id = var.azure_subscription_id
    environment     = var.azure_environment
    # How long create and scale-out wait for the boot-time provisioner, hook holds included.
    provisioning_timeout_minutes = var.provisioning_timeout_minutes
  }
}
