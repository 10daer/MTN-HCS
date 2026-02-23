# HCS Private Cloud — Provider Configuration Notes

## Why HCS differs from public Huawei Cloud

HCS (Huawei Cloud Stack) is an on-premises private cloud. Unlike `myhuaweicloud.com`,
HCS exposes its own IAM endpoint, often with a self-signed certificate. You must
configure the provider with explicit endpoint overrides.

## Required Environment Variables

```bash
export HW_ACCESS_KEY="your-ak"
export HW_SECRET_KEY="your-sk"
export HW_REGION_NAME="your-region"          # as defined in your HCS installation
export HW_DOMAIN_NAME="your-domain"          # account domain name in HCS IAM
export HW_AUTH_URL="https://iam.hcs.example.com/v3"   # private IAM endpoint
export HW_CLOUD_TYPE="private"               # tell provider this is private HCS
```

## Provider Block for Private HCS

```hcl
provider "huaweicloud" {
  auth_url    = var.hcs_auth_url   # https://iam.hcs.example.com/v3
  region      = var.region
  domain_name = var.domain_name
  insecure    = false              # set true ONLY if using self-signed cert
}
```

## Finding Your HCS Endpoints

Ask your HCS administrator for:
- IAM endpoint
- OBS (object storage) endpoint — needed for remote state backend
- Region name as registered in the HCS installation

## Remote State with HCS OBS (S3-compatible)

HCS OBS is S3-compatible. Use the `s3` backend with these settings:

```hcl
terraform {
  backend "s3" {
    bucket   = "myapp-dev-tfstate"
    key      = "dev/terraform.tfstate"
    region   = "your-region"
    endpoint = "https://obs.your-region.hcs.example.com"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
```

Set credentials for OBS via:
```bash
export AWS_ACCESS_KEY_ID="$HW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$HW_SECRET_KEY"
```

## Provider Version

Use `huaweicloud/huaweicloud` version `~> 1.63`. This provider supports both
public Huawei Cloud and private HCS deployments through the same resource types.

Registry: https://registry.terraform.io/providers/huaweicloud/huaweicloud/latest/docs
