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
