#Plan-only tests for the optional NeuralSearch appliance (neuralsearch.tf). Every provider is
#mocked, so no credentials or network access are needed.

mock_provider "azurerm" {}

mock_provider "azurerm" {
  alias = "dns"
}

mock_provider "azapi" {}
mock_provider "random" {}
mock_provider "external" {}

mock_provider "qumulo" {}

override_resource {
  target          = qumulo_filesystem_azure.cluster
  override_during = plan
  values = {
    cluster_version = "7.10.1"
    cluster_reference = {
      cluster_name        = "CNQ-TEST"
      cluster_uuid        = "11111111-1111-1111-1111-111111111111"
      endpoint_ips        = ["10.0.1.10"]
      resource_group_name = "rg-qumulo-test"
      subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
      uses_floating_ips   = true
    }
  }
}

override_data {
  target = data.azurerm_subnet.selected
  values = {
    address_prefixes = ["10.0.1.0/24"]
    service_endpoint = [
      { service = "Microsoft.KeyVault", locations = ["*"] },
      { service = "Microsoft.Storage", locations = ["*"] },
    ]
  }
}

variables {
  admin_pwd_or_keyvault_secret_id = "Plaintext-Test-Passw0rd!"
  azure_subscription_id           = "00000000-0000-0000-0000-000000000000"
  cluster_name                    = "CNQ-TEST"
  cluster_product_type            = "HOT"
  deployment_name                 = "cnq-test-01"
  location                        = "eastus2"
  node_count                      = 3
  resource_group_name             = "rg-qumulo-test"
  subnet_id                       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/my-subnet"
  vm_type                         = "Standard_L8s_v4"
}

run "default_is_disabled" {
  command = plan

  assert {
    condition     = length(qumulo_neuralsearch_azure.search) == 0
    error_message = "NeuralSearch must not be provisioned unless neuralsearch_provision is true."
  }
}

run "enabled" {
  command = plan

  variables {
    neuralsearch_provision = true
  }

  assert {
    condition     = length(qumulo_neuralsearch_azure.search) == 1
    error_message = "neuralsearch_provision = true must create exactly one appliance."
  }

  assert {
    condition     = qumulo_neuralsearch_azure.search[0].deletion_protection == var.deletion_protection
    error_message = "The appliance's deletion_protection must follow var.deletion_protection."
  }

  assert {
    #resource_group_name is optional and computed, so its planned value is unknown and cannot
    #be compared to null. Guard the configuration source instead.
    condition     = !can(regex("(?m)^\\s*resource_group_name\\s*=", file("${path.module}/neuralsearch.tf")))
    error_message = "neuralsearch.tf must not set resource_group_name, so the appliance is created in <cluster_rg>-search and not in the cluster resource group."
  }

  assert {
    condition     = qumulo_neuralsearch_azure.search[0].allow_cidrs == null
    error_message = "allow_cidrs must stay null by default so the VirtualNetwork service tag applies."
  }
}

run "enabled_with_allow_cidrs" {
  command = plan

  variables {
    neuralsearch_provision   = true
    neuralsearch_allow_cidrs = ["10.20.0.0/16"]
  }

  assert {
    condition     = length(qumulo_neuralsearch_azure.search) == 1
    error_message = "neuralsearch_provision = true must create exactly one appliance."
  }

  assert {
    condition     = qumulo_neuralsearch_azure.search[0].allow_cidrs == toset(["10.20.0.0/16"])
    error_message = "neuralsearch_allow_cidrs must pass through to the appliance's allow_cidrs."
  }
}
