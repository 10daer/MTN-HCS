###############################################################################
# Module: cce — Cloud Container Engine
#
# Creates:
#   - CCE cluster (hcs_cce_cluster)
#   - Node pool(s) (hcs_cce_node_pool) — preferred over individual nodes
#   - Namespaces (hcs_cce_namespace)
#   - Data source to query nodes (hcs_cce_nodes)
###############################################################################

# ─────────────────────────────────────────────
# CCE Cluster
# ─────────────────────────────────────────────
locals {
  # CCE allows only lowercase letters, digits and hyphens, must start with a
  # letter and end with a letter or digit. name_prefix routinely contains
  # underscores and uppercase, so sanitise rather than fail at apply time.
  derived_cluster_name = "${trim(lower(replace(var.name_prefix, "/[^a-zA-Z0-9-]/", "-")), "-")}-cluster"
  cluster_name         = var.cluster_name != null ? var.cluster_name : local.derived_cluster_name
}

resource "hcs_cce_cluster" "this" {
  name                   = local.cluster_name
  flavor_id              = var.cluster_flavor_id
  vpc_id                 = var.vpc_id
  subnet_id              = var.subnet_id
  container_network_type = var.container_network_type
  container_network_cidr = var.container_network_cidr
  service_network_cidr   = var.service_network_cidr

  cluster_type        = var.cluster_type
  cluster_version     = var.cluster_version != "" ? var.cluster_version : null
  description         = var.cluster_description
  authentication_mode = var.authentication_mode
  kube_proxy_mode     = var.kube_proxy_mode

  # Optional — expose the K8s API server via an EIP
  eip = var.cluster_eip != "" ? var.cluster_eip : null

  # Multi-AZ for HA flavors (cce.s2.*)
  multi_az = var.cluster_multi_az

  # Tags
  tags = var.tags

  # Cleanup behaviour on cluster delete
  # delete_all covers evs, obs, sfs, efs — the individual flags conflict with it
  delete_all = var.delete_storage_on_destroy ? "true" : "false"

  # Hibernate (useful for dev cost savings)
  hibernate = var.cluster_hibernate

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  lifecycle {
    ignore_changes = [
      cluster_version, # HCS may auto-upgrade patch versions
    ]
  }
}

# ─────────────────────────────────────────────
# Node Pools
# ─────────────────────────────────────────────
resource "hcs_cce_node_pool" "pools" {
  for_each = var.node_pools

  cluster_id         = hcs_cce_cluster.this.id
  name               = "${var.name_prefix}-${each.key}"
  flavor_id          = each.value.flavor_id
  initial_node_count = each.value.initial_node_count
  availability_zone  = each.value.availability_zone
  type               = lookup(each.value, "type", "vm")
  os                 = lookup(each.value, "os", null)
  runtime            = lookup(each.value, "runtime", "containerd")

  # Authentication
  key_pair = var.key_pair_name
  # password = var.node_password  # alternative — use key_pair instead

  # Subnet override (defaults to cluster subnet if not set)
  subnet_id = lookup(each.value, "subnet_id", null)

  # System disk
  root_volume {
    size       = lookup(each.value, "root_volume_size", 50)
    volumetype = lookup(each.value, "root_volume_type", "SSD")
  }

  # Data disk(s)
  dynamic "data_volumes" {
    for_each = lookup(each.value, "data_volumes", [{ size = 100, volumetype = "SSD" }])
    content {
      size       = data_volumes.value.size
      volumetype = data_volumes.value.volumetype
      kms_key_id = lookup(data_volumes.value, "kms_key_id", null)
    }
  }

  # Auto-scaling
  scall_enable             = lookup(each.value, "autoscaling_enabled", false)
  min_node_count           = lookup(each.value, "min_node_count", 0)
  max_node_count           = lookup(each.value, "max_node_count", 0)
  scale_down_cooldown_time = lookup(each.value, "scale_down_cooldown_time", 0)
  priority                 = lookup(each.value, "priority", 1)

  # Kubernetes labels & taints
  labels = lookup(each.value, "labels", {})
  tags   = merge(var.tags, lookup(each.value, "tags", {}))

  dynamic "taints" {
    for_each = lookup(each.value, "taints", [])
    content {
      key    = taints.value.key
      value  = taints.value.value
      effect = taints.value.effect
    }
  }

  # Extended params
  dynamic "extend_params" {
    for_each = lookup(each.value, "max_pods", null) != null || lookup(each.value, "preinstall", null) != null || lookup(each.value, "postinstall", null) != null ? [1] : []
    content {
      max_pods    = lookup(each.value, "max_pods", null)
      preinstall  = lookup(each.value, "preinstall", null)
      postinstall = lookup(each.value, "postinstall", null)
    }
  }

  timeouts {
    create = "30m"
    delete = "30m"
  }
}

# ─────────────────────────────────────────────
# Namespaces
# ─────────────────────────────────────────────
resource "hcs_cce_namespace" "namespaces" {
  for_each = var.namespaces

  cluster_id = hcs_cce_cluster.this.id
  name       = each.key

  labels      = lookup(each.value, "labels", {})
  annotations = lookup(each.value, "annotations", {})
}

# ─────────────────────────────────────────────
# Data source — query cluster nodes (read-only)
# ─────────────────────────────────────────────
data "hcs_cce_nodes" "all" {
  cluster_id = hcs_cce_cluster.this.id

  depends_on = [hcs_cce_node_pool.pools]
}
