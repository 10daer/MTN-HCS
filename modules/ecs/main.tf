###############################################################################
# Module: ecs
#
# Manages ECS resources on Huawei Cloud Stack:
#   - SSH Keypairs              (hcs_ecs_compute_keypair)
#   - Server Groups             (hcs_ecs_compute_server_group)
#   - Instances                 (hcs_ecs_compute_instance)
#   - EIPs + Associations       (hcs_vpc_eip + hcs_ecs_compute_eip_associate)
#   - Volume Attachments        (hcs_ecs_compute_volume_attach)
#   - Interface Attachments     (hcs_ecs_compute_interface_attach)
#   - Snapshots                 (hcs_ecs_compute_snapshot)
#
# Provider: huaweicloud/hcs (Huawei Cloud Stack)
###############################################################################

# ─────────────────────────────────────────────
# Data: discover AZs (used as fallback when instance omits AZ)
# ─────────────────────────────────────────────
data "hcs_availability_zones" "this" {}

# ─────────────────────────────────────────────
# Data: module-level image lookup
# Used when an instance does not supply image_id or its own image_name.
# ─────────────────────────────────────────────
data "hcs_ims_images" "default" {
  name = var.default_image_name
}

# ─────────────────────────────────────────────
# Data: per-instance image lookup
# Only invoked for instances that supply an image_name override.
# ─────────────────────────────────────────────
data "hcs_ims_images" "per_instance" {
  for_each = {
    for k, v in var.instances :
    k => v.image_name
    if v.image_id == null && v.image_name != null
  }

  name = each.value
}

# ─────────────────────────────────────────────
# Locals
# ─────────────────────────────────────────────
locals {
  # Effective AZ list for round-robin fallback
  effective_azs = length(var.default_availability_zones) > 0 ? var.default_availability_zones : data.hcs_availability_zones.this.names

  # Resolve final image ID per instance
  resolved_image_ids = {
    for k, v in var.instances :
    k => (
      v.image_id != null
      ? v.image_id
      : (v.image_name != null
        ? data.hcs_ims_images.per_instance[k].images[0].id
        : data.hcs_ims_images.default.images[0].id
      )
    )
  }

  # Merge module-level SGs with per-instance SGs (deduplicated)
  resolved_sg_ids = {
    for k, v in var.instances :
    k => distinct(concat(var.default_security_group_ids, v.security_group_ids))
  }

  # Instances that need an EIP
  eip_instances = {
    for k, v in var.instances :
    k => v
    if v.assign_eip == true
  }
}

# ─────────────────────────────────────────────
# 1. SSH Keypairs
# ─────────────────────────────────────────────
resource "hcs_ecs_compute_keypair" "this" {
  for_each = var.keypairs

  name       = each.value.name
  key_file   = try(each.value.key_file, null)
  public_key = try(each.value.public_key, null)
}

# ─────────────────────────────────────────────
# 2. Server Groups
# ─────────────────────────────────────────────
resource "hcs_ecs_compute_server_group" "this" {
  for_each = var.server_groups

  name     = each.value.name
  policies = each.value.policies
}

# ─────────────────────────────────────────────
# 3. ECS Instances
# ─────────────────────────────────────────────
resource "hcs_ecs_compute_instance" "this" {
  for_each = var.instances

  name                  = coalesce(each.value.name, "${var.name_prefix}-${each.key}")
  flavor_id             = each.value.flavor_id
  image_id              = local.resolved_image_ids[each.key]
  availability_zone     = coalesce(each.value.availability_zone, local.effective_azs[0])
  security_group_ids    = local.resolved_sg_ids[each.key]
  key_pair              = each.value.key_pair != null ? each.value.key_pair : var.default_key_pair
  admin_pass            = try(each.value.admin_pass, null)
  user_data             = try(each.value.user_data, null)
  power_action          = try(each.value.power_action, null)
  enterprise_project_id = try(each.value.enterprise_project_id, null)

  # ── System disk ─────────────────────────
  system_disk_type = each.value.system_disk_type
  system_disk_size = each.value.system_disk_size
  kms_key_id       = try(each.value.system_kms_key_id, null)
  encrypt_cipher   = try(each.value.encrypt_cipher, null)

  # ── Primary NIC ──────────────────────────
  network {
    uuid              = each.value.subnet_id
    fixed_ip_v4       = try(each.value.fixed_ip_v4, null)
    ipv6_enable       = try(each.value.ipv6_enable, false)
    source_dest_check = try(each.value.source_dest_check, true)
  }

  # ── Extra NICs (secondary networks) ──────
  dynamic "network" {
    for_each = try(each.value.extra_networks, [])
    content {
      uuid              = network.value.subnet_id
      fixed_ip_v4       = try(network.value.fixed_ip_v4, null)
      source_dest_check = try(network.value.source_dest_check, true)
    }
  }

  # ── Inline data disks ─────────────────────
  dynamic "data_disks" {
    for_each = try(each.value.data_disks, [])
    content {
      type           = data_disks.value.type
      size           = data_disks.value.size
      snapshot_id    = try(data_disks.value.snapshot_id, null)
      kms_key_id     = try(data_disks.value.kms_key_id, null)
      encrypt_cipher = try(data_disks.value.encrypt_cipher, null)
    }
  }

  # ── Server group scheduler hint ───────────
  dynamic "scheduler_hints" {
    for_each = try(each.value.server_group_key, null) != null ? [1] : []
    content {
      group = hcs_ecs_compute_server_group.this[each.value.server_group_key].id
    }
  }

  # ── Tags ──────────────────────────────────
  tags = var.tags

  delete_disks_on_termination = each.value.delete_disks_on_termination
  delete_eip_on_termination   = each.value.delete_eip_on_termination

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  lifecycle {
    ignore_changes = [user_data, image_id]
  }

  depends_on = [hcs_ecs_compute_keypair.this]
}

# ─────────────────────────────────────────────
# 4. EIPs for instances that request one
# ─────────────────────────────────────────────
resource "hcs_vpc_eip" "this" {
  for_each = local.eip_instances

  publicip {
    type = each.value.eip_type
  }
  bandwidth {
    name       = "${var.name_prefix}-${each.key}-eip-bw"
    size       = each.value.eip_bandwidth_size
    share_type = "PER"
  }
}

resource "hcs_ecs_compute_eip_associate" "this" {
  for_each = local.eip_instances

  public_ip   = hcs_vpc_eip.this[each.key].address
  instance_id = hcs_ecs_compute_instance.this[each.key].id
}

# ─────────────────────────────────────────────
# 5. Additional Volume Attachments (EVS)
# ─────────────────────────────────────────────
resource "hcs_ecs_compute_volume_attach" "this" {
  for_each = var.volume_attachments

  instance_id = hcs_ecs_compute_instance.this[each.value.instance_key].id
  volume_id   = each.value.volume_id
  device      = try(each.value.device, null)

  timeouts {
    create = "10m"
    delete = "10m"
  }
}

# ─────────────────────────────────────────────
# 6. Interface Attachments (secondary NICs)
# ─────────────────────────────────────────────
resource "hcs_ecs_compute_interface_attach" "this" {
  for_each = var.interface_attachments

  instance_id       = hcs_ecs_compute_instance.this[each.value.instance_key].id
  network_id        = try(each.value.network_id, null)
  port_id           = try(each.value.port_id, null)
  fixed_ip          = try(each.value.fixed_ip, null)
  source_dest_check = try(each.value.source_dest_check, true)

  timeouts {
    create = "10m"
    delete = "10m"
  }
}

# ─────────────────────────────────────────────
# 7. Snapshots
# ─────────────────────────────────────────────
resource "hcs_ecs_compute_snapshot" "this" {
  for_each = var.snapshots

  instance_id = hcs_ecs_compute_instance.this[each.value.instance_key].id
  name        = each.value.name

  timeouts {
    create = "14h"
  }
}
