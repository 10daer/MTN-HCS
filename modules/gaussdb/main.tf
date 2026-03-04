###############################################################################
# Module: gaussdb
#
# Manages GaussDB OpenGauss resources on Huawei Cloud Stack:
#   - Instances           (hcs_gaussdb_opengauss_instance)
#   - Parameter Templates (hcs_gaussdb_opengauss_parameter_template)
#
# Supports distributed, centralized, and hcs2–hcs7 solution modes,
# optional KMS TDE encryption, and custom parameter templates.
#
# Provider: huaweicloud/hcs (Huawei Cloud Stack)
###############################################################################

# ─────────────────────────────────────────────
# Data: Availability Zones
# ─────────────────────────────────────────────
data "hcs_availability_zones" "this" {}

# ─────────────────────────────────────────────
# Data Sources — look up existing instances
# ─────────────────────────────────────────────
data "hcs_gaussdb_opengauss_instance" "existing" {
  for_each = var.existing_instances

  name = each.value.name
}

data "hcs_gaussdb_opengauss_parameter_template" "existing" {
  for_each = var.existing_parameter_templates

  template_id = each.value.template_id
}

# ─────────────────────────────────────────────
# 1. Parameter Templates
# ─────────────────────────────────────────────
resource "hcs_gaussdb_opengauss_parameter_template" "this" {
  for_each = var.parameter_templates

  name                    = each.value.name
  description             = try(each.value.description, null)
  engine_version          = try(each.value.source_configuration_id, null) == null ? each.value.engine_version : null
  instance_mode           = try(each.value.source_configuration_id, null) == null ? each.value.instance_mode : null
  source_configuration_id = try(each.value.source_configuration_id, null)

  dynamic "parameters" {
    for_each = try(each.value.source_configuration_id, null) == null ? try(each.value.parameters, []) : []
    content {
      name  = parameters.value.name
      value = parameters.value.value
    }
  }

  lifecycle {
    ignore_changes = [
      source_configuration_id,
      parameters,
    ]
  }
}

# ─────────────────────────────────────────────
# 2. GaussDB OpenGauss Instances
# ─────────────────────────────────────────────
resource "hcs_gaussdb_opengauss_instance" "this" {
  for_each = var.instances

  # ── Core ──────────────────────────────
  name              = each.value.name
  flavor            = each.value.flavor
  password          = each.value.password
  vpc_id            = each.value.vpc_id
  subnet_id         = each.value.subnet_id
  security_group_id = try(each.value.security_group_id, null)

  # ── Availability Zones ────────────────
  availability_zone = try(
    each.value.availability_zone,
    join(",", slice(
      data.hcs_availability_zones.this.names,
      0,
      min(try(each.value.az_count, 3), length(data.hcs_availability_zones.this.names))
    ))
  )

  # ── Deployment mode ───────────────────
  solution        = try(each.value.solution, null)
  sharding_num    = try(each.value.sharding_num, null)
  coordinator_num = try(each.value.coordinator_num, null)
  replica_num     = try(each.value.replica_num, null)
  port            = try(each.value.port, null)

  # ── HA ────────────────────────────────
  ha {
    mode                 = each.value.ha_mode
    replication_mode     = try(each.value.ha_replication_mode, "sync")
    consistency          = try(each.value.ha_consistency, "strong")
    consistency_protocol = try(each.value.ha_consistency_protocol, null)
  }

  # ── Volume ────────────────────────────
  volume {
    type = each.value.volume_type
    size = each.value.volume_size
  }

  # ── Datastore (optional) ──────────────
  dynamic "datastore" {
    for_each = try(each.value.datastore_engine, null) != null ? [1] : []
    content {
      engine  = each.value.datastore_engine
      version = try(each.value.datastore_version, null)
    }
  }

  # ── Backup strategy (optional) ────────
  dynamic "backup_strategy" {
    for_each = try(each.value.backup_start_time, null) != null ? [1] : []
    content {
      start_time = each.value.backup_start_time
      keep_days  = try(each.value.backup_keep_days, 7)
    }
  }

  # ── KMS TDE encryption (optional) ─────
  kms_tde_key_id   = try(each.value.kms_tde_key_id, null)
  kms_project_name = try(each.value.kms_project_name, null)

  # ── Other optional fields ─────────────
  configuration_id      = try(each.value.configuration_key, null) != null ? local.resolved_template_ids[each.value.configuration_key] : try(each.value.configuration_id, null)
  enterprise_project_id = try(each.value.enterprise_project_id, null)
  time_zone             = try(each.value.time_zone, null)

  # ── Timeouts ──────────────────────────
  timeouts {
    create = try(each.value.timeout_create, "120m")
    update = try(each.value.timeout_update, "90m")
    delete = try(each.value.timeout_delete, "45m")
  }

  lifecycle {
    ignore_changes = [
      password,
      availability_zone,
    ]
  }

  depends_on = [
    hcs_gaussdb_opengauss_parameter_template.this,
  ]
}

# ─────────────────────────────────────────────
# Locals — unified template ID resolution
# ─────────────────────────────────────────────
locals {
  resolved_template_ids = merge(
    { for k, v in hcs_gaussdb_opengauss_parameter_template.this : k => v.id },
    { for k, v in data.hcs_gaussdb_opengauss_parameter_template.existing : "existing:${k}" => v.id },
  )
}
