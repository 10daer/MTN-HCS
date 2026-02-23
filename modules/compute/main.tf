###############################################################################
# Module: compute
# Creates ECS instances (single or a set), attaches EVS system disks,
# optionally attaches EIPs, and registers to a security group.
###############################################################################

# ─────────────────────────────────────────────
# Data: resolve image ID by name filter
# ─────────────────────────────────────────────
data "huaweicloud_images_image" "this" {
  count = var.image_id == null ? 1 : 0

  name        = var.image_name
  most_recent = true
  visibility  = "public"
}

locals {
  resolved_image_id = var.image_id != null ? var.image_id : data.huaweicloud_images_image.this[0].id
}

# ─────────────────────────────────────────────
# ECS Instances
# ─────────────────────────────────────────────
resource "huaweicloud_compute_instance" "this" {
  count = var.instance_count

  name               = format("${var.name_prefix}-ecs-%02d", count.index + 1)
  flavor_id          = var.flavor_id
  image_id           = local.resolved_image_id
  availability_zone  = var.availability_zones[count.index % length(var.availability_zones)]
  security_group_ids = var.security_group_ids
  key_pair           = var.key_pair_name
  user_data          = var.user_data

  # Place in the first private subnet by default; allow override per instance
  network {
    uuid              = var.subnet_ids[count.index % length(var.subnet_ids)]
    fixed_ip_v4       = length(var.fixed_ips) > 0 ? var.fixed_ips[count.index] : null
    source_dest_check = var.source_dest_check
  }

  # System disk
  system_disk_type = var.system_disk_type
  system_disk_size = var.system_disk_size

  # Data disks (optional, same spec for all instances)
  dynamic "data_disks" {
    for_each = var.data_disks
    content {
      type = data_disks.value.type
      size = data_disks.value.size
    }
  }

  # Metadata / cloud-init
  metadata = {
    managed_by = "terraform"
  }

  tags = merge(var.tags, {
    Name  = format("${var.name_prefix}-ecs-%02d", count.index + 1)
    Index = tostring(count.index + 1)
  })

  lifecycle {
    # Prevent accidental destruction of running instances
    ignore_changes = [image_id, user_data]
  }
}

# ─────────────────────────────────────────────
# Optional: EIP per instance
# ─────────────────────────────────────────────
resource "huaweicloud_vpc_eip" "this" {
  count = var.assign_eip ? var.instance_count : 0

  publicip {
    type = var.eip_type
  }
  bandwidth {
    name        = format("${var.name_prefix}-ecs-%02d-bw", count.index + 1)
    size        = var.eip_bandwidth_size
    share_type  = "PER"
    charge_mode = "traffic"
  }
  tags = merge(var.tags, { AttachedTo = format("${var.name_prefix}-ecs-%02d", count.index + 1) })
}

resource "huaweicloud_compute_eip_associate" "this" {
  count = var.assign_eip ? var.instance_count : 0

  public_ip   = huaweicloud_vpc_eip.this[count.index].address
  instance_id = huaweicloud_compute_instance.this[count.index].id
}
