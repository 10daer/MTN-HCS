# Module Deployment: OBS (Object Storage)
## `modules/obs`

> **Prerequisites**: [00-SETUP.md](00-SETUP.md) complete. OBS has **no dependency** on the Network or Security modules.
> **Deploy order**: Any time — OBS is fully independent and can be deployed before or alongside any other module.
> **Estimated apply time**: ~1 minute

---

## What This Module Creates

| Resource | HCS Type | Description |
|---|---|---|
| Buckets | `hcs_obs_bucket` | S3-compatible object storage buckets with full lifecycle config |
| Bucket ACLs | `hcs_obs_bucket_acl` | Fine-grained per-account/owner/public access control |
| Objects | `hcs_obs_bucket_object` | Files or inline content uploaded to buckets |
| Object ACLs | `hcs_obs_bucket_object_acl` | Per-object access control |
| Bucket policies | `hcs_obs_bucket_policy` | IAM-style JSON policies on buckets |

### Bucket naming

All bucket names are auto-prefixed: `<name_prefix>-<key>`.
With `project = "myapp"` and `environment = "dev"`:
- `obs_buckets.logs` → bucket name: `myapp-dev-logs`
- `obs_buckets.artifacts` → bucket name: `myapp-dev-artifacts`

> **OBS bucket names are globally unique** across all HCS tenants. If a name is taken, creation fails. Add a suffix if needed.

---

## Step 1 — Add OBS Values to `terraform.tfvars`

Add or replace the OBS section in `environments/dev/terraform.tfvars`:

### Common pattern — Logs + Artifacts (recommended starting point)

```hcl
# ── OBS — Object Storage ─────────────────────────────────────────────────────
obs_buckets = {

  # Logging bucket — access logs from other buckets flow here
  logs = {
    acl           = "log-delivery-write"   # required for log delivery
    storage_class = "WARM"                 # warm = cheaper for infrequently read logs
    versioning    = false
    force_destroy = true                   # allows terraform destroy even if bucket has objects

    lifecycle_rules = [
      {
        name            = "expire-old-logs"
        prefix          = "access-log/"
        expiration_days = 30               # auto-delete logs after 30 days
      }
    ]
  }

  # Artifact bucket — versioned, with access logging enabled
  artifacts = {
    acl           = "private"
    storage_class = "STANDARD"
    versioning    = true                   # keeps all versions of uploaded files

    logging = {
      target_bucket_key = "logs"           # send access logs to the logs bucket above
      target_prefix     = "access-log/artifacts/"
    }
  }
}
```

### Adding KMS encryption (recommended for sensitive data)

```hcl
obs_buckets = {
  secrets = {
    acl        = "private"
    versioning = true
    encryption = true
    kms_key_id = "<your-kms-key-id>"   # from HCS Console → DEW → KMS → Key ID

    lifecycle_rules = [
      {
        name            = "expire-old-versions"
        prefix          = ""
        expiration_days = 365
      }
    ]
  }
}
```

### Static website bucket

```hcl
obs_buckets = {
  website = {
    acl           = "public-read"
    storage_class = "STANDARD"
    versioning    = false
    force_destroy = true

    website = {
      index_document = "index.html"
      error_document = "error.html"
    }

    cors_rules = [
      {
        allowed_origins = ["https://yourdomain.com"]
        allowed_methods = ["GET", "HEAD"]
        allowed_headers = ["*"]
        max_age_seconds = 3600
      }
    ]
  }
}
```

### Uploading objects to buckets

```hcl
obs_objects = {
  # Inline content
  readme = {
    bucket_key   = "artifacts"            # key from obs_buckets above
    key          = "docs/README.md"       # path within the bucket
    content      = "# Artifacts\nManaged by Terraform."
    content_type = "text/markdown"
  }

  # Upload a local file
  config_file = {
    bucket_key   = "artifacts"
    key          = "config/app.json"
    source       = "files/app.json"      # relative to environments/dev/
    content_type = "application/json"
  }
}
```

### Fine-grained bucket ACL (replaces simple `acl` field)

```hcl
obs_bucket_acls = {
  artifacts_acl = {
    bucket_key = "artifacts"
    owner_permission = {
      access_to_bucket = ["READ", "WRITE"]
      access_to_acl    = ["READ_ACP", "WRITE_ACP"]
    }
    account_permissions = [
      {
        account_id       = "<partner-account-id>"
        access_to_bucket = ["READ"]
        access_to_acl    = ["READ_ACP"]
      }
    ]
  }
}
```

### Bucket policy (S3-compatible JSON)

```hcl
obs_bucket_policies = {
  artifacts_policy = {
    bucket_key    = "artifacts"
    policy_format = "s3"
    policy        = <<-EOF
      {
        "Version": "2012-10-17",
        "Statement": [
          {
            "Sid": "AllowReadFromVPC",
            "Effect": "Allow",
            "Principal": "*",
            "Action": ["s3:GetObject"],
            "Resource": ["arn:aws:s3:::myapp-dev-artifacts/*"]
          }
        ]
      }
    EOF
  }
}
```

---

## Step 2 — Plan the OBS Module

```bash
source ~/.hcs-credentials.sh

cd environments/dev
terraform plan \
  -var-file="terraform.tfvars" \
  -target=module.obs \
  -out=obs.tfplan
```

### What to verify in the plan output

```
# module.obs.hcs_obs_bucket.buckets["logs"] will be created
  + bucket        = "myapp-dev-logs"
  + acl           = "log-delivery-write"
  + storage_class = "WARM"
  + versioning    = false

  + lifecycle_rule {
      + name    = "expire-old-logs"
      + prefix  = "access-log/"
      + expiration { + days = 30 }
    }

# module.obs.hcs_obs_bucket.buckets["artifacts"] will be created
  + bucket        = "myapp-dev-artifacts"
  + acl           = "private"
  + storage_class = "STANDARD"
  + versioning    = true

  + logging {
      + target_bucket = "myapp-dev-logs"
      + target_prefix = "access-log/artifacts/"
    }
```

Confirm:
- ✅ Bucket names include the `myapp-dev-` prefix
- ✅ Versioning is set correctly per bucket
- ✅ Logging target bucket references the correct bucket name
- ✅ KMS key ID appears if encryption is enabled

---

## Step 3 — Apply

```bash
terraform apply obs.tfplan
```

Expected output:
```
module.obs.hcs_obs_bucket.buckets["logs"]: Creating...
module.obs.hcs_obs_bucket.buckets["artifacts"]: Creating...
module.obs.hcs_obs_bucket.buckets["logs"]: Creation complete after 3s
module.obs.hcs_obs_bucket.buckets["artifacts"]: Creation complete after 3s

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

---

## Step 4 — Verify

### View outputs

```bash
cd environments/dev
terraform state show 'module.obs.hcs_obs_bucket.buckets["artifacts"]' | grep bucket_domain_name
# Prints the OBS endpoint URL for the bucket
```

The module outputs:
- `bucket_names` — map of `{ "logs" = "myapp-dev-logs", "artifacts" = "myapp-dev-artifacts" }`
- `resolved_bucket_ids` — map of bucket IDs (for downstream references)
- `bucket_domain_names` — endpoint URLs for each bucket

### Verify in HCS Console

1. Go to **OBS** → **Object Storage**
2. You should see your buckets listed:
   - `myapp-dev-logs`
   - `myapp-dev-artifacts`
3. Click `myapp-dev-artifacts` → **Properties** tab → confirm Versioning = Enabled
4. Check **Lifecycle Rules** on the `logs` bucket — should show the 30-day expiration rule

---

## Referencing Existing Buckets (Not Created by Terraform)

If a bucket already exists in HCS and you want to reference it without adopting it into state:

```hcl
obs_existing_buckets = {
  shared_data = {
    bucket = "company-shared-data-bucket"    # exact bucket name, no prefix applied
  }
}
```

The bucket's ID will appear in `resolved_bucket_ids["existing:shared_data"]` and can be used by other resources.

---

## Lifecycle Rule Reference

| Field | Type | Description |
|---|---|---|
| `name` | string | Unique name for the rule |
| `prefix` | string | Apply rule only to objects with this key prefix (`""` = all objects) |
| `expiration_days` | number | Delete objects after this many days |
| `noncurrent_version_expiration_days` | number | Delete non-current versions after N days (versioned buckets) |

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `BucketAlreadyExists` | Bucket name is taken globally | Add a suffix to make it unique (e.g. `-01`, `-abc`) |
| `target_bucket not found` | Logging `target_bucket_key` references a bucket that doesn't exist yet | Apply the logging-target bucket first, or put both in the same apply |
| `InvalidKMSKeyId` | KMS key ID is wrong or not in your region | Check DEW → KMS in HCS console for the correct key ID |
| `AccessDenied on bucket policy` | Your AK doesn't have `obs:policy:*` permission | Grant OBS policy permissions to the account |
