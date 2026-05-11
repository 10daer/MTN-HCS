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
├── backend.tf.example              # REMOTE state template (HCS OBS — default)
└── backend-local.tf.example        # LOCAL state template (testing / sandbox)
```

## Prerequisites

| Tool      | Minimum Version | Purpose                                           |
| --------- | --------------- | ------------------------------------------------- |
| Terraform | **1.6**         | Required for `terraform test` and `mock_provider` |
| Bash      | 4.0+            | Script runner                                     |

```bash
terraform version   # must be >= 1.6
```

## Documentation

### Setup & Deployment Guides

| Document | Description |
|---|---|
| [docs/00-SETUP.md](docs/00-SETUP.md) | **Start here** — clone, credentials, OBS state bucket, init, validate |
| [docs/01-MODULE-NETWORK.md](docs/01-MODULE-NETWORK.md) | VPC, subnets, NAT gateway (deploy 1st) |
| [docs/02-MODULE-SECURITY.md](docs/02-MODULE-SECURITY.md) | Tiered security groups (deploy 2nd) |
| [docs/03-MODULE-EIP.md](docs/03-MODULE-EIP.md) | Elastic IPs and shared bandwidth pools |
| [docs/04-MODULE-ECS.md](docs/04-MODULE-ECS.md) | Web and app tier ECS instances |
| [docs/05-MODULE-OBS.md](docs/05-MODULE-OBS.md) | Object storage buckets |
| [docs/06-MODULE-VDC.md](docs/06-MODULE-VDC.md) | Users, groups, roles, identity management |
| [docs/07-MODULE-CCE.md](docs/07-MODULE-CCE.md) | Kubernetes cluster and node pools |
| [docs/08-MODULE-GAUSSDB.md](docs/08-MODULE-GAUSSDB.md) | GaussDB OpenGauss instances |
| [docs/09-MODULE-RDS.md](docs/09-MODULE-RDS.md) | RDS MySQL and PostgreSQL instances |
| [docs/TESTING.md](docs/TESTING.md) | Module unit and integration testing guide |
| [docs/LOCAL-VS-REMOTE-STATE.md](docs/LOCAL-VS-REMOTE-STATE.md) | When and how to use local state for personal testing |

### Quick Start — Testing Modules

No credentials required for static and unit tests.

```bash
# Make scripts executable (once after cloning)
chmod +x scripts/*.sh

# Static analysis — fmt + validate — one module
./scripts/test-module.sh network --level static

# Unit tests — mock provider, no credentials
./scripts/test-module.sh ecs --level unit
```

### Quick Start — Deploying an Environment

```bash
# 1. One-time credentials setup
./scripts/setup-credentials.sh

# 2. Load credentials (every new terminal)
source ~/.hcs-credentials.sh

# 3. One-time environment setup (asks: local or remote state?)
./scripts/setup-environment.sh dev

# 4. Initialise, preview, and apply
./scripts/tf.sh dev init
./scripts/tf.sh dev plan
./scripts/tf.sh dev apply
```

See [docs/00-SETUP.md](docs/00-SETUP.md) for the complete step-by-step guide.

### Local state for personal testing

By default, Terraform state is stored remotely in an HCS OBS bucket so the whole team shares it. For personal sandboxing, you can switch any environment to **local state** — a file on your laptop only. Useful for:

- Trying out a module change before opening a PR
- Reproducing a bug without affecting the team's shared state
- Learning Terraform behaviour in a zero-risk way

**Never** use local state for staging or production — state on one developer's laptop cannot be shared, locked, or recovered if the laptop is lost.

Quickest path:

```bash
# Use the wizard — when prompted, type 'local' instead of 'remote'
./scripts/setup-environment.sh dev

# Or switch manually
cp environments/dev/backend-local.tf.example environments/dev/backend.tf
./scripts/tf.sh dev init -reconfigure
```

The `tf.sh` wrapper shows the active backend in its banner (`Backend: LOCAL` or `Backend: REMOTE`) so you always know which one is in use.

Full guide, including how to migrate state between backends: [docs/LOCAL-VS-REMOTE-STATE.md](docs/LOCAL-VS-REMOTE-STATE.md).

## Conventions

- **Naming**: `<name_prefix>-<resource>` e.g. `myapp-dev-vpc`, `myapp-dev-web-sg`
- **Tagging**: All resources carry `Environment`, `Project`, `Owner`, `ManagedBy=terraform`
- **State**: Remote state in HCS OBS by default (one bucket per environment, locking via OBS). A **local backend** option is available for personal testing — see [docs/LOCAL-VS-REMOTE-STATE.md](docs/LOCAL-VS-REMOTE-STATE.md).
- **Secrets**: Never commit credentials. Use `TF_VAR_` environment variables only.
- **Tests**: Every module has a `tests/unit.tftest.hcl` file. Run before every PR.

## Module Dependency Order

When applying incrementally, follow this order:

```
vdc → network → security → eip → ecs / obs / cce / gaussdb / rds
```

In a full `apply`, `depends_on` in `environments/dev/main.tf` handles this automatically.
