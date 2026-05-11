###############################################################################
# Module: obs – Input Variables
#
# Manages OBS buckets, bucket ACLs, bucket objects, object ACLs, and bucket
# policies on Huawei Cloud Stack (HCS).
###############################################################################

# ─────────────────────────────────────────────
# Global
# ─────────────────────────────────────────────
variable "name_prefix" {
  description = "Prefix prepended to bucket names: {name_prefix}-{key}."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Default tags applied to all buckets."
  type        = map(string)
  default     = {}
}

# ─────────────────────────────────────────────
# Buckets
# ─────────────────────────────────────────────
variable "buckets" {
  description = <<-EOT
    Map of OBS buckets to create.
    Key = logical bucket identifier.

    Fields:
      bucket              – (Required) Globally unique bucket name (3-63 chars, DNS-compliant).
                            When omitted, computed as "{name_prefix}-{key}".
      acl                 – (Optional) "private" | "public-read" | "public-read-write" | "log-delivery-write". Default: "private".
      storage_class       – (Optional) "STANDARD" | "WARM" | "COLD". Default: "STANDARD".
      versioning          – (Optional) Bool. Default: false.
      force_destroy       – (Optional) Bool — delete all objects on bucket destroy. Default: false.
      quota               – (Optional) Number — bucket quota in bytes. 0 = unlimited.
      encryption          – (Optional) Bool — enable SSE-KMS.
      kms_key_id          – (Optional) KMS key ID when encryption = true.
      kms_key_project_id  – (Optional) KMS key project ID for cross-project keys.
      parallel_fs         – (Optional) Bool — enable parallel file system.
      enterprise_project_id – (Optional) Enterprise project ID.
      region              – (Optional) Override region.
      cluster_group_id    – (Optional) ForceNew — HCS cluster group.
      bucket_redundancy   – (Optional) "CLASSIC" | "FUSION". Default: "CLASSIC".
      fusion_allow_upgrade    – (Optional) Bool. Default: false.
      fusion_allow_alternative – (Optional) Bool. Default: false.
      policy              – (Optional) Bucket policy JSON string.
      policy_format       – (Optional) "obs" | "s3". Default: "obs".
      logging             – (Optional) object({ target_bucket_key, target_prefix })
                            target_bucket_key references another bucket key in this map.
      website             – (Optional) object({ index_document, error_document, redirect_all_requests_to, routing_rules })
      cors_rules          – (Optional) list(object({ allowed_origins, allowed_methods, allowed_headers, expose_headers, max_age_seconds }))
      lifecycle_rules     – (Optional) list(object({ name, enabled, prefix, expiration_days }))
      tags                – (Optional) map(string) — per-bucket tags merged with var.tags.
  EOT
  type        = any
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.buckets :
      lookup(v, "acl", "private") == "private" ||
      lookup(v, "acl", "private") == "public-read" ||
      lookup(v, "acl", "private") == "public-read-write" ||
      lookup(v, "acl", "private") == "log-delivery-write"
    ])
    error_message = "Each bucket.acl must be one of: private, public-read, public-read-write, log-delivery-write."
  }

  validation {
    condition = alltrue([
      for k, v in var.buckets :
      lookup(v, "storage_class", "STANDARD") == "STANDARD" ||
      lookup(v, "storage_class", "STANDARD") == "WARM" ||
      lookup(v, "storage_class", "STANDARD") == "COLD"
    ])
    error_message = "Each bucket.storage_class must be one of: STANDARD, WARM, COLD."
  }

  validation {
    condition = alltrue([
      for k, v in var.buckets :
      lookup(v, "bucket_redundancy", "CLASSIC") == "CLASSIC" ||
      lookup(v, "bucket_redundancy", "CLASSIC") == "FUSION"
    ])
    error_message = "Each bucket.bucket_redundancy must be CLASSIC or FUSION."
  }
}

# ─────────────────────────────────────────────
# Bucket ACLs (fine-grained)
# ─────────────────────────────────────────────
variable "bucket_acls" {
  description = <<-EOT
    Map of fine-grained bucket ACLs. Key = logical name.
    Replaces any existing ACL on the bucket.

    Fields:
      bucket_key          – (Required) Key referencing a bucket in var.buckets,
                            or "existing:<bucket-name>" for an external bucket.
      owner_permission    – (Optional) object({ access_to_bucket = list(string), access_to_acl = list(string) })
      account_permissions – (Optional) list(object({ account_id, access_to_bucket, access_to_acl }))
      public_permission   – (Optional) object({ access_to_bucket = list(string), access_to_acl = list(string) })
      log_delivery_permission – (Optional) object({ access_to_bucket = list(string), access_to_acl = list(string) })
  EOT
  type        = any
  default     = {}
}

# ─────────────────────────────────────────────
# Bucket Objects
# ─────────────────────────────────────────────
variable "objects" {
  description = <<-EOT
    Map of objects to upload to OBS buckets. Key = logical name.

    Fields:
      bucket_key     – (Required) Key referencing a bucket in var.buckets,
                       or "existing:<bucket-name>" for an external bucket.
      key            – (Required) Object key (path) inside the bucket.
      source         – (Optional) Local file path. Mutually exclusive with content.
      content        – (Optional) Inline content string. Mutually exclusive with source.
      acl            – (Optional) "private" | "public-read" | "public-read-write".
      storage_class  – (Optional) "STANDARD" | "WARM" | "COLD".
      content_type   – (Optional) MIME type.
      etag           – (Optional) Trigger re-upload when file changes.
  EOT
  type        = any
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.objects :
      (lookup(v, "source", null) != null) != (lookup(v, "content", null) != null)
    ])
    error_message = "Each object must have exactly one of 'source' or 'content' (not both, not neither)."
  }
}

# ─────────────────────────────────────────────
# Object ACLs (fine-grained)
# ─────────────────────────────────────────────
variable "object_acls" {
  description = <<-EOT
    Map of fine-grained object ACLs. Key = logical name.

    Fields:
      bucket_key          – (Required) Key referencing a bucket in var.buckets,
                            or "existing:<bucket-name>".
      object_key          – (Required) Key referencing an object in var.objects,
                            or a literal object key path when using an external bucket.
      owner_permission    – (Optional) object({ access_to_object = list(string), access_to_acl = list(string) })
      account_permissions – (Optional) list(object({ account_id, access_to_object, access_to_acl }))
      public_permission   – (Optional) object({ access_to_object = list(string), access_to_acl = list(string) })
  EOT
  type        = any
  default     = {}
}

# ─────────────────────────────────────────────
# Bucket Policies
# ─────────────────────────────────────────────
variable "bucket_policies" {
  description = <<-EOT
    Map of bucket policies to apply. Key = logical name.

    Fields:
      bucket_key    – (Required) Key referencing a bucket in var.buckets,
                      or "existing:<bucket-name>".
      policy        – (Required) Policy JSON string.
      policy_format – (Optional) "obs" | "s3". Default: "obs".
  EOT
  type        = any
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.bucket_policies :
      lookup(v, "policy_format", "obs") == "obs" ||
      lookup(v, "policy_format", "obs") == "s3"
    ])
    error_message = "Each bucket_policy.policy_format must be 'obs' or 's3'."
  }
}

# ─────────────────────────────────────────────
# Data-source lookups for existing resources
# ─────────────────────────────────────────────
variable "existing_buckets" {
  description = <<-EOT
    Map of existing OBS buckets to look up via data source.
    Key = lookup alias; value = { bucket = "<bucket-name>" }.
    Referenced as "existing:<key>" in bucket_key fields.
  EOT
  type = map(object({
    bucket = string
  }))
  default = {}
}
