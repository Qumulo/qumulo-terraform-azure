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

output "cluster_name" {
  description = "Name of the Qumulo cluster"
  value       = qumulo_filesystem_azure.cluster.cluster_reference.cluster_name
}

output "cluster_uuid" {
  description = "UUID of the Qumulo cluster"
  value       = qumulo_filesystem_azure.cluster.cluster_reference.cluster_uuid
}

output "resource_group_unique_name" {
  description = "The deployment's Azure resource group name (resource_group_name verbatim; retained under this name so existing tooling keeps working). Do not share this group with any other VMs; on Qumulo Core versions below 7.10.1 this is a hard requirement -- see main.tf."
  value       = local.resource_group_unique_name
}

output "deployment_unique_name" {
  description = "Unique deployment identifier"
  value       = qumulo_filesystem_azure.cluster.deployment_unique_name
}

output "endpoint_ips" {
  description = "Client-facing IPs. Floating IPs if configured, otherwise primary node IPs."
  value       = qumulo_filesystem_azure.cluster.endpoint_ips
}

output "primary_ips" {
  description = "Per-node primary IPs. Use these directly when no floating IPs are configured, or for per-node access."
  value       = qumulo_filesystem_azure.cluster.primary_ips
}

output "provisioner_log_url" {
  description = "Azure portal deep link to this deployment's provisioner log workspace (table QumuloProvisioner_CL, 30-day retention). Opens the workspace's Logs blade, not the log content directly -- unlike CloudWatch, Log Analytics is query-first: the portal may first show a \"Queries hub\" gallery, which must be dismissed (its close/X control) to reach the query editor, where running `QumuloProvisioner_CL | order by TimeGenerated asc | project TimeGenerated, RawData` displays the log. The provisioner VM is deleted after the operation completes, so this workspace is the only place the log survives; tools/get-provisioner-log.sh/.ps1 run that same query via the CLI and write the result straight to a text file, skipping the portal UI entirely."
  value = format(
    "https://%s/#resource/subscriptions/%s/resourceGroups/%s/providers/Microsoft.OperationalInsights/workspaces/%s/logs",
    var.azure_environment == "usgovernment" ? "portal.azure.us" : "portal.azure.com",
    var.azure_subscription_id,
    local.resource_group_unique_name,
    "${qumulo_filesystem_azure.cluster.deployment_unique_name}-logs",
  )
}

output "soft_capacity_limit_tb" {
  description = "Total capacity the cluster may consume.  Only used capacity is billed."
  value       = qumulo_filesystem_azure.cluster.soft_capacity_limit_tb
}

output "endpoints" {
  description = "Connection endpoints for various protocols"
  value = {
    web_ui = "https://${try(qumulo_filesystem_azure.cluster.endpoint_ips[0], "pending")}"
    api    = "https://${try(qumulo_filesystem_azure.cluster.endpoint_ips[0], "pending")}:8000"
    nfs    = "${try(qumulo_filesystem_azure.cluster.endpoint_ips[0], "pending")}:/<NFS Export Name>"
    smb    = "\\${try(qumulo_filesystem_azure.cluster.endpoint_ips[0], "pending")}\\<SMB Share Name>"
  }
}

output "private_endpoints" {
  description = "Every private endpoint serving this deployment (storage accounts, Key Vault, App Configuration). The feed for external DNS systems such as Infoblox: publish an A record fqdn -> ip_address for each entry, and use target_resource_id to disable public network access once the records serve."
  value = concat(
    [for pe in values(local.storage_pes) : merge(pe, { service = "storage" })],
    local.keyvault_pe != null ? [merge(local.keyvault_pe, { service = "keyvault" })] : [],
    local.appconfig_pe != null ? [merge(local.appconfig_pe, { service = "appconfig" })] : [],
  )
}

output "private_dns_records" {
  description = "fqdn -> private IP of the Azure Private DNS A records the wrapper created. Empty when the zone variables are unset (external-DNS path)."
  value       = try(module.private_dns[0].records, {})
}
