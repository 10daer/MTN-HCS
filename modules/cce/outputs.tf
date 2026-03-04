###############################################################################
# Module: cce — Outputs
###############################################################################

# ─────────────────────────────────────────────
# Cluster
# ─────────────────────────────────────────────
output "cluster_id" {
  description = "ID of the CCE cluster"
  value       = hcs_cce_cluster.this.id
}

output "cluster_name" {
  description = "Name of the CCE cluster"
  value       = hcs_cce_cluster.this.name
}

output "cluster_status" {
  description = "Current status of the CCE cluster"
  value       = hcs_cce_cluster.this.status
}

output "kube_config_raw" {
  description = "Raw kubeconfig for kubectl access"
  value       = hcs_cce_cluster.this.kube_config_raw
  sensitive   = true
}

output "certificate_clusters" {
  description = "Cluster certificate data (server address + CA)"
  value       = hcs_cce_cluster.this.certificate_clusters
}

output "certificate_users" {
  description = "User certificate data (client cert + key)"
  value       = hcs_cce_cluster.this.certificate_users
  sensitive   = true
}

# ─────────────────────────────────────────────
# Node Pools
# ─────────────────────────────────────────────
output "node_pool_ids" {
  description = "Map of node pool name keys to their IDs"
  value       = { for k, v in hcs_cce_node_pool.pools : k => v.id }
}

output "node_pool_statuses" {
  description = "Map of node pool name keys to their status"
  value       = { for k, v in hcs_cce_node_pool.pools : k => v.status }
}

output "node_pool_current_counts" {
  description = "Map of node pool name keys to their current node count"
  value       = { for k, v in hcs_cce_node_pool.pools : k => v.current_node_count }
}

# ─────────────────────────────────────────────
# Nodes (data source)
# ─────────────────────────────────────────────
output "node_ids" {
  description = "List of all node IDs in the cluster"
  value       = data.hcs_cce_nodes.all.ids
}

output "nodes" {
  description = "Full list of node details"
  value       = data.hcs_cce_nodes.all.nodes
}

# ─────────────────────────────────────────────
# Namespaces
# ─────────────────────────────────────────────
output "namespace_names" {
  description = "List of created namespace names"
  value       = [for ns in hcs_cce_namespace.namespaces : ns.name]
}

output "namespace_statuses" {
  description = "Map of namespace names to their status"
  value       = { for k, v in hcs_cce_namespace.namespaces : k => v.status }
}
