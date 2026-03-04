###############################################################################
# Module: obs – Outputs
###############################################################################

# ── Buckets ──────────────────────────────────────────────────────────────────
output "bucket_ids" {
  description = "Map of bucket keys to their IDs (bucket names)."
  value       = { for k, v in hcs_obs_bucket.this : k => v.id }
}

output "bucket_names" {
  description = "Map of bucket keys to their bucket names."
  value       = { for k, v in hcs_obs_bucket.this : k => v.bucket }
}

output "bucket_domain_names" {
  description = "Map of bucket keys to their domain names."
  value       = { for k, v in hcs_obs_bucket.this : k => v.bucket_domain_name }
}

output "bucket_versions" {
  description = "Map of bucket keys to their bucket version."
  value       = { for k, v in hcs_obs_bucket.this : k => v.bucket_version }
}

output "bucket_regions" {
  description = "Map of bucket keys to their region."
  value       = { for k, v in hcs_obs_bucket.this : k => v.region }
}

output "bucket_storage_info" {
  description = "Map of bucket keys to storage info ({ size, object_number })."
  value       = { for k, v in hcs_obs_bucket.this : k => v.storage_info }
}

# ── Objects ──────────────────────────────────────────────────────────────────
output "object_ids" {
  description = "Map of object keys to their IDs."
  value       = { for k, v in hcs_obs_bucket_object.this : k => v.id }
}

output "object_etags" {
  description = "Map of object keys to their ETags."
  value       = { for k, v in hcs_obs_bucket_object.this : k => v.etag }
}

output "object_version_ids" {
  description = "Map of object keys to their version IDs (when versioning is enabled)."
  value       = { for k, v in hcs_obs_bucket_object.this : k => v.version_id }
}

output "object_sizes" {
  description = "Map of object keys to their sizes in bytes."
  value       = { for k, v in hcs_obs_bucket_object.this : k => v.size }
}

# ── Resolved references (managed + existing) ────────────────────────────────
output "resolved_bucket_ids" {
  description = "All resolved bucket IDs — managed buckets + existing data-source buckets."
  value       = local.resolved_bucket_ids
}
