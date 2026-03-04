# Terraform HCS (Huawei Cloud Stack) Infrastructure Repository

## Repository Structure

```
terraform-hcs-repo/
├── modules/                  # Reusable Terraform modules
│   ├── network/              # VPC, subnets, security groups, ELB
│   ├── compute/              # ECS instances, auto-scaling groups
│   ├── storage/              # EVS volumes, OBS buckets, SFS
│   ├── iam/                  # IAM users, roles, policies
│   └── security/             # Security groups, WAF, VPN
├── environments/             # Per-environment root configurations
│   ├── dev/
│   ├── staging/
│   └── prod/
├── scripts/                  # Helper scripts (init, plan, apply, destroy)
├── docs/                     # Architecture and runbook docs
├── .github/workflows/        # CI/CD pipelines
├── versions.tf               # Provider and Terraform version constraints
├── backend.tf.example        # Remote state backend template
└── .terraform-version        # tfenv version pin
```

## Prerequisites

- Terraform >= 1.5.0 (use [tfenv](https://github.com/tfutils/tfenv))
- HCS credentials (Access Key + Secret Key)
- Remote state bucket pre-created in HCS OBS (optional — can use local state)

## Quick Start

```bash
# 1. Clone and navigate
git clone <repo>
cd terraform-hcs-repo

# 2. Install correct Terraform version
tfenv install

# 3. Set credentials (Terraform reads TF_VAR_ prefixed env vars automatically)
export TF_VAR_access_key="your-ak"
export TF_VAR_secret_key="your-sk"

# 4. Init an environment
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your region, domain, project, and endpoints
terraform init -backend=false   # use -backend=false for local state
terraform plan
terraform apply
```

## Conventions

- **Naming**: `{project}-{environment}-{resource}-{index}` e.g. `myapp-dev-ecs-01`
- **Tagging**: All resources must carry `Environment`, `Project`, `Owner`, `ManagedBy=terraform`
- **State**: Remote state in HCS OBS, one bucket per environment, state locking via OBS
- **Secrets**: Never commit credentials. Use environment variables or HCS KMS references.
- **Modules**: Always pin module sources to a git tag or commit SHA.
