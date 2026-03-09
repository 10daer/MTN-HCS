###############################################################################
# Unit tests: obs module
#
# Uses mock_provider — no HCS credentials required.
# Run:
#   cd modules/obs && terraform test
#   ./scripts/test-module.sh obs --level unit
###############################################################################

mock_provider "hcs" {
  mock_data "hcs_obs_buckets" {
    defaults = {
      buckets = [{ bucket = "existing-bucket-name" }]
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1: Empty buckets map creates nothing
# ─────────────────────────────────────────────────────────────────────────────
run "empty_buckets" {
  command = apply

  variables {
    name_prefix = "test"
    buckets     = {}
  }

  assert {
    condition     = length(hcs_obs_bucket.this) == 0
    error_message = "No buckets should be created when buckets map is empty"
  }

  assert {
    condition     = output.bucket_ids == {}
    error_message = "bucket_ids must be empty"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: Bucket name defaults to <name_prefix>-<key>
# ─────────────────────────────────────────────────────────────────────────────
run "bucket_name_auto_generated" {
  command = apply

  variables {
    name_prefix = "myapp-dev"
    buckets = {
      logs    = {}
      backups = {}
    }
  }

  assert {
    condition     = hcs_obs_bucket.this["logs"].bucket == "myapp-dev-logs"
    error_message = "Bucket name should be '<name_prefix>-<key>' when bucket field not set"
  }

  assert {
    condition     = hcs_obs_bucket.this["backups"].bucket == "myapp-dev-backups"
    error_message = "Backup bucket name should be '<name_prefix>-backups'"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: Explicit bucket name overrides the auto-generated name
# ─────────────────────────────────────────────────────────────────────────────
run "explicit_bucket_name" {
  command = apply

  variables {
    name_prefix = "myapp-dev"
    buckets = {
      static = { bucket = "my-custom-bucket-name" }
    }
  }

  assert {
    condition     = hcs_obs_bucket.this["static"].bucket == "my-custom-bucket-name"
    error_message = "Explicit bucket name must override the auto-generated name"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4: Default ACL is private, versioning off, STANDARD storage
# ─────────────────────────────────────────────────────────────────────────────
run "bucket_defaults" {
  command = apply

  variables {
    name_prefix = "test"
    buckets = {
      data = {}
    }
  }

  assert {
    condition     = hcs_obs_bucket.this["data"].acl == "private"
    error_message = "Default ACL must be 'private'"
  }

  assert {
    condition     = hcs_obs_bucket.this["data"].storage_class == "STANDARD"
    error_message = "Default storage class must be 'STANDARD'"
  }

  assert {
    condition     = hcs_obs_bucket.this["data"].versioning == false
    error_message = "Versioning must be disabled by default"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 5: Versioning can be enabled, KMS encryption applied
# ─────────────────────────────────────────────────────────────────────────────
run "bucket_with_versioning_and_encryption" {
  command = apply

  variables {
    name_prefix = "test"
    buckets = {
      secure = {
        versioning = true
        kms_key_id = "mock-kms-key-id"
      }
    }
  }

  assert {
    condition     = hcs_obs_bucket.this["secure"].versioning == true
    error_message = "Versioning must be enabled"
  }

  assert {
    condition     = hcs_obs_bucket.this["secure"].encryption == true
    error_message = "Encryption must be true when kms_key_id is set"
  }

  assert {
    condition     = hcs_obs_bucket.this["secure"].kms_key_id == "mock-kms-key-id"
    error_message = "KMS key ID must be applied to the bucket"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 6: Multiple buckets with different storage classes
# ─────────────────────────────────────────────────────────────────────────────
run "multiple_buckets_different_tiers" {
  command = apply

  variables {
    name_prefix = "test"
    buckets = {
      hot  = { storage_class = "STANDARD" }
      warm = { storage_class = "WARM" }
      cold = { storage_class = "COLD" }
    }
  }

  assert {
    condition     = length(hcs_obs_bucket.this) == 3
    error_message = "Three buckets should be created"
  }

  assert {
    condition     = hcs_obs_bucket.this["cold"].storage_class == "COLD"
    error_message = "Cold bucket must use COLD storage class"
  }
}
