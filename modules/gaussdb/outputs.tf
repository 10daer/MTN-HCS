###############################################################################
# Module: gaussdb – Outputs
###############################################################################

# ── Instances ────────────────────────────────
output "instance_ids" {
  description = "Map of instance keys to their IDs."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.id }
}

output "instance_names" {
  description = "Map of instance keys to their names."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.name }
}

output "instance_status" {
  description = "Map of instance keys to their status."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.status }
}

output "instance_type" {
  description = "Map of instance keys to their deployment type."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.type }
}

output "instance_private_ips" {
  description = "Map of instance keys to their private IP lists."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.private_ips }
}

output "instance_public_ips" {
  description = "Map of instance keys to their public IP lists."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.public_ips }
}

output "instance_endpoints" {
  description = "Map of instance keys to their connection endpoints."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.endpoints }
}

output "instance_db_user_name" {
  description = "Map of instance keys to the default database username."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.db_user_name }
}

output "instance_nodes" {
  description = "Map of instance keys to their node details."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.nodes }
}

output "instance_ha" {
  description = "Map of instance keys to their HA configuration."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.ha }
}

output "instance_volume" {
  description = "Map of instance keys to their volume configuration."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.volume }
}

output "instance_datastore" {
  description = "Map of instance keys to their datastore info."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.datastore }
}

output "instance_backup_strategy" {
  description = "Map of instance keys to their backup strategy."
  value       = { for k, v in hcs_gaussdb_opengauss_instance.this : k => v.backup_strategy }
}

# ── Parameter Templates ─────────────────────
output "template_ids" {
  description = "Map of template keys to their IDs."
  value       = { for k, v in hcs_gaussdb_opengauss_parameter_template.this : k => v.id }
}

output "template_names" {
  description = "Map of template keys to their names."
  value       = { for k, v in hcs_gaussdb_opengauss_parameter_template.this : k => v.name }
}

# ── Resolved IDs (for downstream modules) ───
output "all_template_ids" {
  description = "Merged map of managed + existing parameter template IDs."
  value       = local.resolved_template_ids
}

# ── Availability Zones (convenience) ────────
output "available_zones" {
  description = "List of availability zone names discovered by the module."
  value       = data.hcs_availability_zones.this.names
}
