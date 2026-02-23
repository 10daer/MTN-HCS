###############################################################################
# Module: storage
# Creates OBS buckets and standalone EVS volumes (for manual attachment).
###############################################################################

# ─────────────────────────────────────────────
# OBS Buckets
# ─────────────────────────────────────────────
resource "huaweicloud_obs_bucket" "this" {
  for_each = var.obs_buckets

  bucket        = "${var.name_prefix}-${each.key}"
  acl           = lookup(each.value, "acl", "private")
  storage_class = lookup(each.value, "storage_class", "STANDARD")
  force_destroy = lookup(each.value, "force_destroy", false)

  # Versioning
  dynamic "versioning" {
    for_each = lookup(each.value, "versioning", false) ? [1] : []
    content {
      enabled = true
    }
  }

  # Server-side encryption with KMS
  dynamic "server_side_encryption" {
    for_each = lookup(each.value, "kms_key_id", null) != null ? [1] : []
    content {
      algorithm  = "aws:kms"
      kms_key_id = each.value.kms_key_id
    }
  }

  # Lifecycle rules
  dynamic "lifecycle_rule" {
    for_each = lookup(each.value, "lifecycle_rules", [])
    content {
      name    = lifecycle_rule.value.name
      enabled = true
      prefix  = lookup(lifecycle_rule.value, "prefix", "")

      dynamic "expiration" {
        for_each = lookup(lifecycle_rule.value, "expiration_days", null) != null ? [1] : []
        content {
          days = lifecycle_rule.value.expiration_days
        }
      }
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })
}

# ─────────────────────────────────────────────
# Standalone EVS Volumes (for separate attachment)
# ─────────────────────────────────────────────
resource "huaweicloud_evs_volume" "this" {
  for_each = var.evs_volumes

  name              = "${var.name_prefix}-${each.key}"
  availability_zone = each.value.availability_zone
  volume_type       = lookup(each.value, "type", "SSD")
  size              = each.value.size
  multiattach       = lookup(each.value, "multiattach", false)

  # KMS encryption
  kms_id = lookup(each.value, "kms_key_id", null)

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })
}
