###############################################################################
# Module: rds – Outputs
###############################################################################

# ── Instances ────────────────────────────────────────────────────────────────
output "instance_ids" {
  description = "Map of instance keys to their IDs."
  value       = { for k, v in hcs_rds_instance.this : k => v.id }
}

output "instance_private_ips" {
  description = "Map of instance keys to their private IP lists."
  value       = { for k, v in hcs_rds_instance.this : k => v.private_ips }
}

output "instance_public_ips" {
  description = "Map of instance keys to their public IP lists."
  value       = { for k, v in hcs_rds_instance.this : k => v.public_ips }
}

output "instance_status" {
  description = "Map of instance keys to their status."
  value       = { for k, v in hcs_rds_instance.this : k => v.status }
}

output "instance_nodes" {
  description = "Map of instance keys to their node details."
  value       = { for k, v in hcs_rds_instance.this : k => v.nodes }
}

output "instance_db_user_names" {
  description = "Map of instance keys to their default DB user name."
  value       = { for k, v in hcs_rds_instance.this : k => v.db[0].user_name }
}

# ── MySQL Databases ──────────────────────────────────────────────────────────
output "mysql_database_names" {
  description = "Map of MySQL database keys to their names."
  value       = { for k, v in hcs_rds_mysql_database.this : k => v.name }
}

# ── MySQL Accounts ───────────────────────────────────────────────────────────
output "mysql_account_names" {
  description = "Map of MySQL account keys to their names."
  value       = { for k, v in hcs_rds_mysql_account.this : k => v.name }
}

# ── PostgreSQL Databases ─────────────────────────────────────────────────────
output "pg_database_names" {
  description = "Map of PostgreSQL database keys to their names."
  value       = { for k, v in hcs_rds_pg_database.this : k => v.name }
}

# ── PostgreSQL Accounts ──────────────────────────────────────────────────────
output "pg_account_names" {
  description = "Map of PostgreSQL account keys to their names."
  value       = { for k, v in hcs_rds_pg_account.this : k => v.name }
}

# ── Resolved references (managed + existing) ────────────────────────────────
output "resolved_instance_ids" {
  description = "All resolved instance IDs — managed + existing data-source instances."
  value       = local.resolved_instance_ids
}
