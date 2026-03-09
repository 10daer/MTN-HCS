# MTN-HCS — Huawei Cloud Stack Terraform Repository

## Repository Structure

```
MTN-HCS/
├── modules/                        # Reusable Terraform modules (one per service)
│   ├── network/                    # VPC, subnets, NAT gateway, security groups
│   ├── security/                   # Security groups + ingress/egress rules
│   ├── ecs/                        # ECS instances, keypairs, server groups, EIPs
│   ├── eip/                        # Dedicated & shared EIPs, shared bandwidth
│   ├── obs/                        # OBS buckets (versioning, encryption, lifecycle)
│   ├── rds/                        # RDS MySQL / PostgreSQL instances and accounts
│   ├── gaussdb/                    # GaussDB OpenGauss instances
│   ├── cce/                        # CCE Kubernetes clusters, node pools, namespaces
│   ├── vdc/                        # VDC users, groups, roles, projects
│   └── iam/                        # Placeholder (HCS does not support IAM via TF)
│       └── tests/
│           ├── unit.tftest.hcl     # Mock-provider unit tests (no credentials)
│           └── integration.tftest.hcl  # Real-provider plan tests (optional)
├── environments/                   # Per-environment root configurations
│   ├── dev/
│   ├── staging/
│   └── prod/
├── scripts/
│   ├── tf.sh                       # Environment launcher (init / plan / apply / destroy)
│   ├── test-module.sh              # Unified module test runner (static / unit / integration)
│   ├── setup-credentials.sh        # One-time machine credential setup
│   └── setup-environment.sh        # One-time per-environment config setup
├── docs/
│   ├── TESTING.md                  # Full testing guide ← start here
│   └── *.md                        # Per-service design docs
└── backend.tf.example              # Remote state backend template
```

## Prerequisites

| Tool      | Minimum Version | Purpose                                           |
| --------- | --------------- | ------------------------------------------------- |
| Terraform | **1.6**         | Required for `terraform test` and `mock_provider` |
| Bash      | 4.0+            | Script runner                                     |

```bash
terraform version   # must be >= 1.6
```

## Quick Start — Testing Modules

No credentials required for static and unit tests.

```bash
# Make scripts executable (once after cloning)
chmod +x scripts/*.sh

# Static analysis — fmt + validate — one module
./scripts/test-module.sh network --level static

# Unit tests — mock provider, no credentials
./scripts/test-module.sh ecs --level unit

# Run all modules, all levels (static + unit)
./scripts/test-module.sh --all --level static
./scripts/test-module.sh --all --level unit
```

See [docs/TESTING.md](docs/TESTING.md) for the full guide.

## Quick Start — Deploying an Environment

```bash
# 1. Set credentials
export TF_VAR_access_key="AK..."
export TF_VAR_secret_key="SK..."

# 2. One-time environment setup (creates backend.tf + terraform.tfvars)
./scripts/setup-environment.sh dev

# 3. Initialise, preview, and apply
./scripts/tf.sh dev init
./scripts/tf.sh dev plan
./scripts/tf.sh dev apply
```

See [SETUP-INSTRUCTIONS.md](SETUP-INSTRUCTIONS.md) for full first-time setup.

## Conventions

- **Naming**: `<name_prefix>-<resource>` e.g. `myapp-dev-vpc`, `myapp-dev-web-sg`
- **Tagging**: All resources carry `Environment`, `Project`, `Owner`, `ManagedBy=terraform`
- **State**: Remote state in HCS OBS, one bucket per environment, state locking via OBS
- **Secrets**: Never commit credentials. Use `TF_VAR_` environment variables only.
- **Tests**: Every module has a `tests/unit.tftest.hcl` file. Run before every PR.

## Module Dependency Order

When applying incrementally, follow this order:

```
vdc → network → security → eip → ecs / obs / cce / gaussdb / rds
```

In a full `apply`, `depends_on` in `environments/dev/main.tf` handles this automatically.
