###############################################################################
# Module: rds
# Manages RDS instances (MySQL / PostgreSQL), databases, accounts, privileges,
# plugins, and SQL audit on Huawei Cloud Stack (HCS).
#
# Provider: huaweicloud/hcs ~> 2.4.0
###############################################################################

# ─────────────────────────────────────────────
# Locals
# ─────────────────────────────────────────────
locals {
  # Resolved instance IDs — managed + existing
  resolved_instance_ids = merge(
    { for k, v in hcs_rds_instance.this : k => v.id },
    { for k, v in data.hcs_rds_instance.existing : "existing:${k}" => v.id }
  )

  # Convenience: private IPs per instance
  resolved_private_ips = {
    for k, v in hcs_rds_instance.this : k => v.private_ips
  }
}

# ─────────────────────────────────────────────
# Data Sources — Existing instances
# ─────────────────────────────────────────────
data "hcs_rds_instance" "existing" {
  for_each = var.existing_instances

  name = each.value.name
}

# ─────────────────────────────────────────────
# 1. RDS Instances
# ─────────────────────────────────────────────
resource "hcs_rds_instance" "this" {
  for_each = var.instances

  name              = each.value.name
  flavor            = each.value.flavor
  vpc_id            = each.value.vpc_id
  subnet_id         = each.value.subnet_id
  security_group_id = each.value.security_group_id
  availability_zone = each.value.availability_zone

  # HA replication
  ha_replication_mode = lookup(each.value, "ha_replication_mode", null)

  # Database engine
  db {
    type     = each.value.db_type
    version  = each.value.db_version
    password = each.value.db_password
    port     = lookup(each.value, "db_port", null)
  }

  # Volume
  volume {
    type = each.value.volume_type
    size = each.value.volume_size
  }

  # Backup strategy
  dynamic "backup_strategy" {
    for_each = lookup(each.value, "backup_start_time", null) != null ? [1] : []
    content {
      start_time = each.value.backup_start_time
      keep_days  = lookup(each.value, "backup_keep_days", 7)
      period     = lookup(each.value, "backup_period", null)
    }
  }

  # Custom parameters
  dynamic "parameters" {
    for_each = lookup(each.value, "parameters", [])
    content {
      name  = parameters.value.name
      value = parameters.value.value
    }
  }

  # Optional fields
  lower_case_table_names = lookup(each.value, "lower_case_table_names", null)
  time_zone              = lookup(each.value, "time_zone", null)
  ssl_enable             = lookup(each.value, "ssl_enable", null)
  description            = lookup(each.value, "description", null)
  enterprise_project_id  = lookup(each.value, "enterprise_project_id", null)
  param_group_id         = lookup(each.value, "param_group_id", null)
  tags                   = lookup(each.value, "tags", null)

  timeouts {
    create = lookup(each.value, "timeout_create", "30m")
    update = lookup(each.value, "timeout_update", "30m")
    delete = lookup(each.value, "timeout_delete", "30m")
  }

  lifecycle {
    ignore_changes = [db, param_group_id, availability_zone]
  }
}

# ─────────────────────────────────────────────
# 2. MySQL Databases
# ─────────────────────────────────────────────
resource "hcs_rds_mysql_database" "this" {
  for_each = var.mysql_databases

  instance_id   = local.resolved_instance_ids[each.value.instance_key]
  name          = each.value.name
  character_set = each.value.character_set
  description   = each.value.description
}

# ─────────────────────────────────────────────
# 3. MySQL Accounts
# ─────────────────────────────────────────────
resource "hcs_rds_mysql_account" "this" {
  for_each = var.mysql_accounts

  instance_id = local.resolved_instance_ids[each.value.instance_key]
  name        = each.value.name
  password    = each.value.password
  hosts       = each.value.hosts
}

# ─────────────────────────────────────────────
# 4. MySQL Database Privileges
# ─────────────────────────────────────────────
resource "hcs_rds_mysql_database_privilege" "this" {
  for_each = var.mysql_privileges

  instance_id = local.resolved_instance_ids[each.value.instance_key]
  db_name     = hcs_rds_mysql_database.this[each.value.db_key].name

  dynamic "users" {
    for_each = each.value.users
    content {
      name     = hcs_rds_mysql_account.this[users.value.account_key].name
      readonly = users.value.readonly
    }
  }
}

# ─────────────────────────────────────────────
# 5. PostgreSQL Databases
# ─────────────────────────────────────────────
resource "hcs_rds_pg_database" "this" {
  for_each = var.pg_databases

  instance_id = local.resolved_instance_ids[each.value.instance_key]
  name        = each.value.name
  owner       = each.value.owner
}

# ─────────────────────────────────────────────
# 6. PostgreSQL Accounts
# ─────────────────────────────────────────────
resource "hcs_rds_pg_account" "this" {
  for_each = var.pg_accounts

  instance_id = local.resolved_instance_ids[each.value.instance_key]
  name        = each.value.name
  password    = each.value.password
}

# ─────────────────────────────────────────────
# 7. PostgreSQL Database Privileges
# ─────────────────────────────────────────────
resource "hcs_rds_pg_database_privilege" "this" {
  for_each = var.pg_privileges

  instance_id = local.resolved_instance_ids[each.value.instance_key]
  db_name     = hcs_rds_pg_database.this[each.value.db_key].name

  dynamic "users" {
    for_each = each.value.users
    content {
      name        = hcs_rds_pg_account.this[users.value.account_key].name
      schema_name = users.value.schema_name
      readonly    = users.value.readonly
    }
  }
}

# ─────────────────────────────────────────────
# 8. PostgreSQL Plugins
# ─────────────────────────────────────────────
resource "hcs_rds_pg_plugin" "this" {
  for_each = var.pg_plugins

  instance_id   = local.resolved_instance_ids[each.value.instance_key]
  database_name = hcs_rds_pg_database.this[each.value.db_key].name
  name          = each.value.name
}

# ─────────────────────────────────────────────
# 9. SQL Audit
# ─────────────────────────────────────────────
resource "hcs_rds_sql_audit" "this" {
  for_each = var.sql_audits

  instance_id = local.resolved_instance_ids[each.value.instance_key]
  keep_days   = each.value.keep_days
  audit_types = each.value.audit_types
}
