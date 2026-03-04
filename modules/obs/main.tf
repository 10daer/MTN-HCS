###############################################################################
# Module: obs
# Manages OBS buckets, bucket ACLs, bucket objects, object ACLs, and bucket
# policies on Huawei Cloud Stack (HCS).
#
# Provider: huaweicloud/hcs ~> 2.4.0
###############################################################################

# ─────────────────────────────────────────────
# Locals — Resolve bucket names/IDs
# ─────────────────────────────────────────────
locals {
  # Compute the actual bucket name for each managed bucket
  bucket_names = {
    for k, v in var.buckets :
    k => lookup(v, "bucket", var.name_prefix != "" ? "${var.name_prefix}-${k}" : k)
  }

  # Merge managed bucket IDs + existing bucket names for cross-reference
  resolved_bucket_ids = merge(
    { for k, v in hcs_obs_bucket.this : k => v.id },
    { for k, v in data.hcs_obs_buckets.existing : "existing:${k}" => v.buckets[0].bucket }
  )

  # Merge managed object keys for cross-reference
  resolved_object_keys = {
    for k, v in hcs_obs_bucket_object.this : k => v.key
  }
}

# ─────────────────────────────────────────────
# Data Sources — Look up existing buckets
# ─────────────────────────────────────────────
data "hcs_obs_buckets" "existing" {
  for_each = var.existing_buckets

  bucket = each.value.bucket
}

# ─────────────────────────────────────────────
# 1. OBS Buckets
# ─────────────────────────────────────────────
resource "hcs_obs_bucket" "this" {
  for_each = var.buckets

  bucket        = local.bucket_names[each.key]
  acl           = lookup(each.value, "acl", "private")
  storage_class = lookup(each.value, "storage_class", "STANDARD")
  versioning    = lookup(each.value, "versioning", false)
  force_destroy = lookup(each.value, "force_destroy", false)

  # Optional overrides
  quota                = lookup(each.value, "quota", null)
  parallel_fs          = lookup(each.value, "parallel_fs", null)
  enterprise_project_id = lookup(each.value, "enterprise_project_id", null)
  region               = lookup(each.value, "region", null)
  cluster_group_id     = lookup(each.value, "cluster_group_id", null)

  # Fusion bucket
  bucket_redundancy        = lookup(each.value, "bucket_redundancy", null)
  fusion_allow_upgrade     = lookup(each.value, "fusion_allow_upgrade", null)
  fusion_allow_alternative = lookup(each.value, "fusion_allow_alternative", null)

  # Encryption — SSE-KMS
  encryption         = lookup(each.value, "kms_key_id", null) != null ? true : lookup(each.value, "encryption", false)
  kms_key_id         = lookup(each.value, "kms_key_id", null)
  kms_key_project_id = lookup(each.value, "kms_key_project_id", null)

  # Inline policy (simple case — for standalone policies use bucket_policies variable)
  policy        = lookup(each.value, "policy", null)
  policy_format = lookup(each.value, "policy_format", null)

  # Custom domain names
  dynamic "user_domain_names" {
    for_each = lookup(each.value, "user_domain_names", null) != null ? each.value.user_domain_names : []
    content {
      name = user_domain_names.value
    }
  }

  # Logging — target_bucket_key references another key in var.buckets
  dynamic "logging" {
    for_each = lookup(each.value, "logging", null) != null ? [each.value.logging] : []
    content {
      target_bucket = (
        startswith(logging.value.target_bucket_key, "existing:")
        ? local.resolved_bucket_ids[logging.value.target_bucket_key]
        : hcs_obs_bucket.this[logging.value.target_bucket_key].id
      )
      target_prefix = lookup(logging.value, "target_prefix", "log/")
    }
  }

  # Static website hosting
  dynamic "website" {
    for_each = lookup(each.value, "website", null) != null ? [each.value.website] : []
    content {
      index_document           = lookup(website.value, "index_document", null)
      error_document           = lookup(website.value, "error_document", null)
      redirect_all_requests_to = lookup(website.value, "redirect_all_requests_to", null)
      routing_rules            = lookup(website.value, "routing_rules", null)
    }
  }

  # CORS rules
  dynamic "cors_rule" {
    for_each = lookup(each.value, "cors_rules", [])
    content {
      allowed_origins = cors_rule.value.allowed_origins
      allowed_methods = cors_rule.value.allowed_methods
      allowed_headers = lookup(cors_rule.value, "allowed_headers", null)
      expose_headers  = lookup(cors_rule.value, "expose_headers", null)
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", null)
    }
  }

  # Lifecycle rules
  dynamic "lifecycle_rule" {
    for_each = lookup(each.value, "lifecycle_rules", [])
    content {
      name    = lifecycle_rule.value.name
      enabled = lookup(lifecycle_rule.value, "enabled", true)
      prefix  = lookup(lifecycle_rule.value, "prefix", "")

      dynamic "expiration" {
        for_each = lookup(lifecycle_rule.value, "expiration_days", null) != null ? [1] : []
        content {
          days = lifecycle_rule.value.expiration_days
        }
      }
    }
  }

  tags = merge(var.tags, lookup(each.value, "tags", {}))

  lifecycle {
    ignore_changes = [acl, force_destroy]
  }
}

# ─────────────────────────────────────────────
# 2. Bucket ACLs (fine-grained, overwrites existing)
# ─────────────────────────────────────────────
resource "hcs_obs_bucket_acl" "this" {
  for_each = var.bucket_acls

  bucket = (
    startswith(each.value.bucket_key, "existing:")
    ? local.resolved_bucket_ids[each.value.bucket_key]
    : hcs_obs_bucket.this[each.value.bucket_key].id
  )

  # Owner permissions
  dynamic "owner_permission" {
    for_each = lookup(each.value, "owner_permission", null) != null ? [each.value.owner_permission] : []
    content {
      access_to_bucket = lookup(owner_permission.value, "access_to_bucket", [])
      access_to_acl    = lookup(owner_permission.value, "access_to_acl", [])
    }
  }

  # Per-account permissions
  dynamic "account_permission" {
    for_each = lookup(each.value, "account_permissions", [])
    content {
      account_id       = account_permission.value.account_id
      access_to_bucket = lookup(account_permission.value, "access_to_bucket", [])
      access_to_acl    = lookup(account_permission.value, "access_to_acl", [])
    }
  }

  # Public permissions
  dynamic "public_permission" {
    for_each = lookup(each.value, "public_permission", null) != null ? [each.value.public_permission] : []
    content {
      access_to_bucket = lookup(public_permission.value, "access_to_bucket", [])
      access_to_acl    = lookup(public_permission.value, "access_to_acl", [])
    }
  }

  # Log-delivery permissions
  dynamic "log_delivery_permission" {
    for_each = lookup(each.value, "log_delivery_permission", null) != null ? [each.value.log_delivery_permission] : []
    content {
      access_to_bucket = lookup(log_delivery_permission.value, "access_to_bucket", [])
      access_to_acl    = lookup(log_delivery_permission.value, "access_to_acl", [])
    }
  }
}

# ─────────────────────────────────────────────
# 3. Bucket Objects
# ─────────────────────────────────────────────
resource "hcs_obs_bucket_object" "this" {
  for_each = var.objects

  bucket = (
    startswith(each.value.bucket_key, "existing:")
    ? local.resolved_bucket_ids[each.value.bucket_key]
    : hcs_obs_bucket.this[each.value.bucket_key].id
  )

  key           = each.value.key
  source        = lookup(each.value, "source", null)
  content       = lookup(each.value, "content", null)
  acl           = lookup(each.value, "acl", null)
  storage_class = lookup(each.value, "storage_class", null)
  content_type  = lookup(each.value, "content_type", null)
  etag          = lookup(each.value, "etag", null)

  lifecycle {
    ignore_changes = [source, acl]
  }
}

# ─────────────────────────────────────────────
# 4. Object ACLs (fine-grained, overwrites existing)
# ─────────────────────────────────────────────
resource "hcs_obs_bucket_object_acl" "this" {
  for_each = var.object_acls

  bucket = (
    startswith(each.value.bucket_key, "existing:")
    ? local.resolved_bucket_ids[each.value.bucket_key]
    : hcs_obs_bucket.this[each.value.bucket_key].id
  )

  key = (
    contains(keys(var.objects), lookup(each.value, "object_key", ""))
    ? hcs_obs_bucket_object.this[each.value.object_key].key
    : each.value.object_key
  )

  # Owner permissions
  dynamic "owner_permission" {
    for_each = lookup(each.value, "owner_permission", null) != null ? [each.value.owner_permission] : []
    content {
      access_to_object = lookup(owner_permission.value, "access_to_object", [])
      access_to_acl    = lookup(owner_permission.value, "access_to_acl", [])
    }
  }

  # Per-account permissions
  dynamic "account_permission" {
    for_each = lookup(each.value, "account_permissions", [])
    content {
      account_id       = account_permission.value.account_id
      access_to_object = lookup(account_permission.value, "access_to_object", [])
      access_to_acl    = lookup(account_permission.value, "access_to_acl", [])
    }
  }

  # Public permissions
  dynamic "public_permission" {
    for_each = lookup(each.value, "public_permission", null) != null ? [each.value.public_permission] : []
    content {
      access_to_object = lookup(public_permission.value, "access_to_object", [])
      access_to_acl    = lookup(public_permission.value, "access_to_acl", [])
    }
  }
}

# ─────────────────────────────────────────────
# 5. Bucket Policies (standalone — separate from inline bucket policy)
# ─────────────────────────────────────────────
resource "hcs_obs_bucket_policy" "this" {
  for_each = var.bucket_policies

  bucket = (
    startswith(each.value.bucket_key, "existing:")
    ? local.resolved_bucket_ids[each.value.bucket_key]
    : hcs_obs_bucket.this[each.value.bucket_key].id
  )

  policy        = each.value.policy
  policy_format = lookup(each.value, "policy_format", "obs")
}
