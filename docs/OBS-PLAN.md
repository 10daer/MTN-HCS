````markdown
# Huawei Cloud Stack (HCS) OBS Terraform Context

**Purpose**  
This file is the complete authoritative reference for any LLM (including yourself) when designing or generating Terraform configurations for Object Storage Service (OBS) resources in Huawei Cloud Stack.

Use this document to ensure all generated code follows the official schemas, bucket naming rules, ACL behavior, policy formats (OBS vs S3), encryption options, fusion bucket constraints, and lifecycle rules.

---

## Supported Resources

### 1. hcs_obs_bucket (Resource)

**Description:** Manages an OBS bucket.

**Example Usage**

**Private Bucket with Tags**

```hcl
resource "hcs_obs_bucket" "private" {
  bucket = "my-tf-test-bucket"
  acl    = "private"

  tags = {
    Env  = "Test"
    Team = "DevOps"
  }
}
```
````

**Versioning Enabled**

```hcl
resource "hcs_obs_bucket" "versioned" {
  bucket     = "my-tf-test-bucket"
  acl        = "private"
  versioning = true
}
```

**Logging**

```hcl
resource "hcs_obs_bucket" "log" {
  bucket = "my-tf-log-bucket"
  acl    = "log-delivery-write"
}

resource "hcs_obs_bucket" "main" {
  bucket = "my-tf-main-bucket"
  acl    = "private"

  logging {
    target_bucket = hcs_obs_bucket.log.id
    target_prefix = "log/"
  }
}
```

**Static Website Hosting**

```hcl
resource "hcs_obs_bucket" "website" {
  bucket = "obs-website-test.example.com"
  acl    = "public-read"

  website {
    index_document = "index.html"
    error_document = "error.html"
    routing_rules  = <<EOF
[{
  "Condition": { "KeyPrefixEquals": "docs/" },
  "Redirect": { "ReplaceKeyPrefixWith": "documents/" }
}]
EOF
  }
}
```

**CORS**

```hcl
resource "hcs_obs_bucket" "cors" {
  bucket = "obs-website-test.example.com"
  acl    = "public-read"

  cors_rule {
    allowed_origins = ["https://example.com"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
```

**Lifecycle Rule**

```hcl
resource "hcs_obs_bucket" "lifecycle" {
  bucket     = "my-bucket"
  acl        = "private"
  versioning = true

  lifecycle_rule {
    name    = "archive-logs"
    prefix  = "logs/"
    enabled = true

    expiration {
      days = 90
    }
  }
}
```

**Fusion Bucket**

```hcl
resource "hcs_obs_bucket" "fusion" {
  bucket                   = "my-fusion-bucket"
  acl                      = "private"
  storage_class            = "STANDARD"
  bucket_redundancy        = "FUSION"
  fusion_allow_upgrade     = true
  fusion_allow_alternative = true
}
```

**Argument Reference**

- `bucket` – (Required, String, ForceNew) 3-63 chars, globally unique, DNS-compliant rules (see full constraints in original doc).
- `acl` – (Optional) `private` (default), `public-read`, `public-read-write`, etc.
- `storage_class` – (Optional) `STANDARD` (default), `WARM`, `COLD`.
- `versioning` – (Optional, Bool)
- `policy` / `policy_format` (`obs` or `s3`)
- `tags`
- `logging`, `website`, `cors_rule[]`, `lifecycle_rule[]`
- `encryption`, `kms_key_id`, `kms_key_project_id`
- `bucket_redundancy` (`CLASSIC` or `FUSION`), `fusion_allow_upgrade`, `fusion_allow_alternative`
- `parallel_fs`, `quota`, `force_destroy`, `enterprise_project_id`, `user_domain_names[]`
- `region`, `cluster_group_id` (ForceNew)

**Nested Blocks**

- `logging` → `target_bucket`, `target_prefix`
- `website` → `index_document`, `error_document`, `redirect_all_requests_to`, `routing_rules`
- `cors_rule` → `allowed_origins`, `allowed_methods`, `allowed_headers`, `expose_headers`, `max_age_seconds`
- `lifecycle_rule` → `name`, `enabled`, `prefix`, `expiration { days }`

**Attributes Reference**

- `id`, `bucket_domain_name`, `bucket_version`, `region`, `storage_info { size, object_number }`

**Import**

```bash
terraform import hcs_obs_bucket.example <bucket-name>
# For S3 policy format:
terraform import hcs_obs_bucket.example <bucket-name>/s3
```

**Recommended lifecycle**

```hcl
lifecycle {
  ignore_changes = [acl, force_destroy]
}
```

---

### 2. hcs_obs_bucket_acl (Resource)

**Description:** Manages detailed ACL for an OBS bucket (overwrites existing ACL).

**Example Usage**

```hcl
resource "hcs_obs_bucket_acl" "custom" {
  bucket = hcs_obs_bucket.main.id

  owner_permission {
    access_to_bucket = ["READ", "WRITE"]
    access_to_acl    = ["READ_ACP", "WRITE_ACP"]
  }

  account_permission {
    account_id       = var.account1
    access_to_bucket = ["READ", "WRITE"]
    access_to_acl    = ["READ_ACP", "WRITE_ACP"]
  }

  public_permission {
    access_to_bucket = ["READ"]
  }
}
```

**Note:** Deleting this resource resets to owner-only permissions.

**Import:** by bucket name

---

### 3. hcs_obs_bucket_object (Resource)

**Description:** Manages an object inside an OBS bucket.

**Examples**

- From `content`
- From `source` (file)

**Argument Reference**

- `bucket`, `key` (ForceNew)
- `source` or `content` (mutually exclusive)
- `acl`, `storage_class`, `content_type`, `etag`

**Import:** `<bucket>/<key>`

**Recommended lifecycle**

```hcl
lifecycle {
  ignore_changes = [source, acl]
}
```

---

### 4. hcs_obs_bucket_object_acl (Resource)

**Description:** Manages detailed ACL for a specific object (overwrites existing).

**Example Usage** similar to bucket ACL but for object level.

**Import:** `<bucket>/<key>`

**Note:** Deleting resets to owner-only.

---

### 5. hcs_obs_bucket_policy (Resource)

**Description:** Manages bucket policy (OBS or S3 format).

**Examples**

- OBS format
- S3 format (with `policy_format = "s3"`)

**Import**

- OBS: by bucket
- S3: `<bucket>/s3`

---

## Data Sources

### hcs_obs_bucket_object

```hcl
data "hcs_obs_bucket_object" "obj" {
  bucket = "my-bucket"
  key    = "path/to/file.txt"
}
```

### hcs_obs_buckets

```hcl
data "hcs_obs_buckets" "all" {
  bucket = "my-bucket"   # optional filter
}
```

---

## Usage Guidelines for LLM Code Generation

1. **Bucket Naming** – strictly follow the DNS rules (3-63 chars, no IP, no consecutive ./- etc.).
2. **ACL Strategy** – use `hcs_obs_bucket` for simple ACL, use `hcs_obs_bucket_acl` for fine-grained owner/account/public/log-delivery permissions.
3. **Policy Format** – default `obs`; use `s3` only when you need AWS-compatible policies.
4. **Versioning + Lifecycle** – enable versioning first, then add lifecycle rules for expiration/transition.
5. **Encryption** – set `encryption = true` + `kms_key_id` for SSE-KMS.
6. **Fusion Buckets** – set `bucket_redundancy = "FUSION"` + `fusion_allow_upgrade = true`.
7. **Objects** – prefer `source` for files, `content` for inline small text. Always set proper `content_type`.
8. **Import** – always run `terraform plan` after import and ignore `acl`, `force_destroy`, `source`.
9. **Common Pattern** – one bucket + logging bucket + lifecycle + versioning + CORS for static websites.

You now have the complete, clean OBS context.

Would you like a full production-ready module that demonstrates:

- Private bucket with versioning + lifecycle
- Fusion bucket
- Static website + CORS
- Object upload + object ACL
- Bucket policy (S3 format)
- Logging bucket

Just say the word and I’ll generate it instantly!

```

```
