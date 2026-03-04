# HCS Private Cloud — Provider Configuration Notes

## Why HCS differs from public Huawei Cloud

HCS (Huawei Cloud Stack) is an on-premises private cloud. Unlike `myhuaweicloud.com`,
HCS exposes its own service endpoints, often with self-signed certificates. You must
configure the provider with explicit endpoint overrides.

This repo uses the **`huaweicloud/hcs`** provider (not `huaweicloud/huaweicloud`).
Resource types are `hcs_*` (e.g. `hcs_vpc`, `hcs_ecs_compute_instance`).

## Required Environment Variables

```bash
export TF_VAR_access_key="your-ak"
export TF_VAR_secret_key="your-sk"
```

All other config (region, domain, endpoints) lives in `terraform.tfvars`:

```hcl
region       = "MTN_Cloud"
domain_name  = "IT-DEPT"
project_name = "lagos-mtn-1_A_and_E"
hcs_auth_url = ""

endpoints = {
  ecs = "https://ecs.lagos-mtn-1.mtn.com"
  ims = "https://ims.lagos-mtn-1.mtn.com"
  vpc = "https://vpc.lagos-mtn-1.mtn.com"
  evs = "https://evs.lagos-mtn-1.mtn.com"
  nat = "https://nat.lagos-mtn-1.mtn.com"
  obs = "https://obs.lagos-mtn-1.mtn.com"
  iam = "https://iam-apigateway-proxy.mtn.com"
}
```

## Provider Block

```hcl
provider "hcs" {
  access_key   = var.access_key
  secret_key   = var.secret_key
  region       = var.region
  domain_name  = var.domain_name
  project_name = var.project_name
  auth_url     = var.hcs_auth_url
  insecure     = var.skip_tls_verify

  endpoints = var.endpoints
}
```

## Finding Your HCS Endpoints

Ask your HCS administrator for:

- Service endpoints (ECS, VPC, IMS, EVS, NAT, OBS, IAM)
- Region name as registered in the HCS installation
- Domain/tenant name and project/VDC name

## Remote State with HCS OBS (S3-compatible)

HCS OBS is S3-compatible. Use the `s3` backend:

```hcl
terraform {
  backend "s3" {
    bucket   = "myapp-dev-tfstate"
    key      = "dev/terraform.tfstate"
    region   = "MTN_Cloud"
    endpoint = "https://obs.lagos-mtn-1.mtn.com"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
```

Set credentials for OBS via:

```bash
export AWS_ACCESS_KEY_ID="$TF_VAR_access_key"
export AWS_SECRET_ACCESS_KEY="$TF_VAR_secret_key"
```

## Provider Version

Use `huaweicloud/hcs` version `~> 2.4.0`. This is the dedicated provider for
HCS (Huawei Cloud Stack) private deployments.

Registry: https://registry.terraform.io/providers/huaweicloud/hcs/latest/docs
