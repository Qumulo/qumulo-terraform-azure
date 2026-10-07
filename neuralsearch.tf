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

#Optional Qumulo NeuralSearch appliance. It is a single VM placed in the cluster's VNet and
#subnet. It lives in its own resource group, <cluster_rg>-search, and serves a web UI on
#TCP 443 at its private IP. The VM needs outbound HTTPS at first boot. SSH (user qsadmin)
#is available only when ssh_public_key_path is set.
#
#resource_group_name is deliberately not set. The provider default <cluster_rg>-search keeps
#the appliance out of the cluster resource group, which the floating-IP reconciler
#check in main.tf requires to stay dedicated to the cluster.
resource "qumulo_neuralsearch_azure" "search" {
  count    = var.neuralsearch_provision ? 1 : 0
  provider = qumulo

  allow_cidrs         = var.neuralsearch_allow_cidrs
  cluster_reference   = qumulo_filesystem_azure.cluster.cluster_reference
  deletion_protection = var.deletion_protection
  ssh_public_key      = local.ssh_public_key
  tags                = var.tags
  vm_type             = var.neuralsearch_vm_type

  timeouts {
    create = "${tostring(coalesce(var.provider_create_timeout_minutes, var.provider_timeout_minutes))}m"
    delete = "${tostring(coalesce(var.provider_delete_timeout_minutes, var.provider_timeout_minutes))}m"
    update = "${tostring(coalesce(var.provider_update_timeout_minutes, var.provider_timeout_minutes))}m"
  }
}
