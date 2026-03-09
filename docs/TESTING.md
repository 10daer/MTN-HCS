# Module Testing & Launch Guide

## Overview

This guide describes the **three-layer testing strategy** for every Terraform module in this repository. The system is designed so that:

- **Static checks and unit tests run entirely without HCS credentials** — safe for local development, code review, and CI pipelines.
- **Integration tests target a real HCS environment** — reserved for pre-deployment validation.
- **All tests can be invoked through a single script**, with optional targeting of individual modules.

---

## Architecture of the Testing System

```
modules/
└── <module>/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── versions.tf
    └── tests/
        ├── unit.tftest.hcl           ← Layer 2: mock-provider unit tests
        └── integration.tftest.hcl    ← Layer 3: real-provider plan tests (optional)

scripts/
├── test-module.sh    ← unified test runner
└── tf.sh             ← environment launcher (plan / apply / destroy)
```

---

## Prerequisites

| Tool                | Minimum Version | Purpose                                           |
| ------------------- | --------------- | ------------------------------------------------- |
| Terraform           | **1.6**         | Required for `terraform test` and `mock_provider` |
| Bash                | 4.0+            | Test runner script                                |
| tflint _(optional)_ | any             | Additional linting beyond `terraform validate`    |

Check your version:

```bash
terraform version
```

If below 1.6, upgrade from [developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads).

---

## The Three Testing Layers

### Layer 1 — Static Analysis

**What it does:** Checks formatting and validates the HCL syntax of a module without making any network calls.

**When to use:** Before every commit. Runs in seconds. No credentials needed.

**Commands:**

```bash
# Check formatting of a single module
terraform fmt -check -recursive modules/network

# Auto-fix formatting
terraform fmt -recursive modules/network

# Validate a module
cd modules/network
terraform init -backend=false
terraform validate
```

**Via the test runner:**

```bash
./scripts/test-module.sh network --level static
./scripts/test-module.sh --all --level static   # check every module
```

---

### Layer 2 — Unit Tests (Mock Provider)

**What it does:** Runs `terraform test` against the module using a `mock_provider "hcs" {}` declaration. The mock provider intercepts all resource API calls and returns synthetic values — no real infrastructure is created. This validates:

- Module logic and conditional branching (e.g. `enable_nat_gateway = false` creates zero NAT resources)
- `for_each` creates the correct number of resources
- Naming conventions (`<name_prefix>-<suffix>`)
- Output map shapes and content
- Default values are applied correctly

**When to use:** During feature development, in CI for all PRs, after any module change.

**Commands:**

```bash
# Run unit tests for one module
cd modules/network
terraform init -backend=false
terraform test

# From anywhere, via the test runner
./scripts/test-module.sh network --level unit
./scripts/test-module.sh --all --level unit
```

**How mock_provider works:**

```hcl
# Example from modules/network/tests/unit.tftest.hcl
mock_provider "hcs" {}

run "nat_gateway_disabled" {
  command = apply         # ← "apply" with mock never calls the real API

  variables {
    name_prefix        = "test"
    vpc_cidr           = "10.0.0.0/16"
    enable_nat_gateway = false
    ...
  }

  assert {
    condition     = length(hcs_nat_gateway.this) == 0
    error_message = "Expected no NAT gateway when enable_nat_gateway = false"
  }
}
```

The `command = apply` inside a test run with `mock_provider` resolves all computed attributes to mock values (generated UUIDs, etc.) so you can assert on outputs and resource counts. The `command = plan` variant is also available but cannot assert on computed attributes.

**Data source overrides:** For modules whose logic depends on the content of a data source (e.g. `data.hcs_ims_images.default.images[0].id`), the test file uses `mock_data` blocks to inject controlled values:

```hcl
mock_provider "hcs" {
  mock_data "hcs_ims_images" {
    defaults = {
      images = [{ id = "mock-image-id", name = "Ubuntu 22.04 server 64bit" }]
    }
  }
  mock_data "hcs_availability_zones" {
    defaults = {
      names = ["az1.dc0", "az2.dc0"]
    }
  }
}
```

---

### Layer 3 — Integration Tests (Real Provider, Plan Only)

**What it does:** Runs `terraform test` against the real HCS provider using the read-only `command = plan` mode. No resources are created or modified. This validates that:

- The HCS provider can authenticate and reach its endpoints
- Resource attribute types line up with the real API schema
- Data source lookups resolve against live infrastructure

**When to use:** Before deploying to a new environment, or when the HCS provider version is updated.

**Credentials required:**

```bash
export TF_VAR_access_key="<your-AK>"
export TF_VAR_secret_key="<your-SK>"
```

**Command:**

```bash
./scripts/test-module.sh network --level integration
```

Integration test files are named `integration.tftest.hcl` and live alongside the unit tests in `modules/<module>/tests/`. They are **not included** when running `--level unit` — the test runner filters them by filename.

---

## Module Quick Reference

| Module     | Unit Tests           | Integration Tests | Key Variables to Provide                                |
| ---------- | -------------------- | ----------------- | ------------------------------------------------------- |
| `network`  | ✅ `unit.tftest.hcl` | —                 | `name_prefix`, `vpc_cidr`, `availability_zones`         |
| `security` | ✅ `unit.tftest.hcl` | —                 | `name_prefix`, `security_groups`                        |
| `ecs`      | ✅ `unit.tftest.hcl` | —                 | `name_prefix`, `instances` map                          |
| `eip`      | ✅ `unit.tftest.hcl` | —                 | `name_prefix`, `dedicated_eips` or `shared_bandwidths`  |
| `obs`      | ✅ `unit.tftest.hcl` | —                 | `name_prefix`, `buckets` map                            |
| `rds`      | ✅ `unit.tftest.hcl` | —                 | `instances` map with `db_type`, `db_version`, `flavor`  |
| `gaussdb`  | ✅ `unit.tftest.hcl` | —                 | `instances` map with `ha_mode`, `volume_type`, `flavor` |
| `cce`      | ✅ `unit.tftest.hcl` | —                 | `name_prefix`, `vpc_id`, `subnet_id`, `key_pair_name`   |
| `vdc`      | ✅ `unit.tftest.hcl` | —                 | `vdc_id`, `users`/`groups`/`roles` maps                 |
| `iam`      | —                    | —                 | HCS does not support IAM via Terraform                  |

---

## Testing a Single Module

### Complete test run (all layers)

```bash
./scripts/test-module.sh network
```

### Static only

```bash
./scripts/test-module.sh security --level static
```

### Unit tests only

```bash
./scripts/test-module.sh ecs --level unit
```

### Integration tests only (credentials required)

```bash
export TF_VAR_access_key="AK..."
export TF_VAR_secret_key="SK..."
./scripts/test-module.sh rds --level integration
```

---

## Testing All Modules at Once

```bash
# Run everything (static + unit + integration if credentials present)
./scripts/test-module.sh --all

# Static analysis pass for every module (CI pre-check)
./scripts/test-module.sh --all --level static

# Full unit test suite (no credentials needed)
./scripts/test-module.sh --all --level unit
```

Produces a summary table at the end:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PASS  network
  PASS  security
  PASS  ecs
  PASS  eip
  PASS  obs
  PASS  rds
  PASS  gaussdb
  PASS  cce
  PASS  vdc
  SKIP  iam
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ALL PASSED
```

---

## Launching an Environment with `tf.sh`

`tf.sh` is the **deployment launcher** for complete environments. It operates on the `environments/<env>/` directory and does not run individual module tests — it manages the lifecycle of a full stack.

### Environment commands

```bash
# Full syntax
./scripts/tf.sh <environment> <command> [options]
```

| Command     | What it does                                                        |
| ----------- | ------------------------------------------------------------------- |
| `init`      | Initialises Terraform, downloads providers, connects to OBS backend |
| `validate`  | Checks syntax without calling any API (no credentials needed)       |
| `fmt`       | Auto-formats all `.tf` files across the repo                        |
| `plan`      | Generates a plan for the whole environment                          |
| `apply`     | Applies the last saved plan                                         |
| `destroy`   | Destroys all resources (requires typed confirmation)                |
| `output`    | Shows all Terraform outputs from current state                      |
| `state`     | Pass-through to `terraform state` (`list`, `show`, `rm`, etc.)      |
| `refresh`   | Refreshes local state from live HCS resources                       |
| `console`   | Opens an interactive Terraform console for debugging expressions    |
| `unlock`    | Force-unlocks a stuck state lock                                    |
| `workspace` | Shows current workspace info                                        |

### Launching `dev`

```bash
# 1. Export credentials
export TF_VAR_access_key="AK..."
export TF_VAR_secret_key="SK..."

# 2. One-time setup (creates backend.tf + terraform.tfvars interactively)
./scripts/setup-environment.sh dev

# 3. Initialise
./scripts/tf.sh dev init

# 4. Preview changes
./scripts/tf.sh dev plan

# 5. Apply
./scripts/tf.sh dev apply
```

### Targeting a specific module inside an environment

Use Terraform's `-target` flag to plan or apply only one module at a time. This is useful for incremental rollouts and debugging.

```bash
# Plan only the network module
./scripts/tf.sh dev plan -- -target=module.network

# Apply only the security module after network is up
./scripts/tf.sh dev apply -- -target=module.security

# Plan a specific ECS tier
./scripts/tf.sh dev plan -- -target=module.web
./scripts/tf.sh dev plan -- -target=module.app

# Inspect state for one module
./scripts/tf.sh dev state list -- -state=environments/dev/terraform.tfstate | grep "^module.network"
```

> **Important:** `tf.sh` passes everything after `--` directly to Terraform, so the `-- ` separator is required when using flags not natively understood by the script.

### Recommended deployment order

Module dependencies in this repo form a directed graph. When applying incrementally or for the first time, follow this order to avoid missing input values:

```
vdc  →  network  →  security  →  eip  →  web (ecs) / app (ecs)
                                       →  obs
                                       →  cce
                                       →  gaussdb
                                       →  rds
```

In practice, since `depends_on` is declared in `environments/dev/main.tf`, a plain `apply` respects this order automatically.

---

## Writing New Module Tests

### File naming convention

| File                                          | Purpose                                                          |
| --------------------------------------------- | ---------------------------------------------------------------- |
| `modules/<name>/tests/unit.tftest.hcl`        | Mock-provider tests — committed to repo, run in CI               |
| `modules/<name>/tests/integration.tftest.hcl` | Real-provider plan tests — optional, skipped without credentials |

### Minimal unit test structure

```hcl
# modules/<name>/tests/unit.tftest.hcl

mock_provider "hcs" {}          # always the first line

run "descriptive_test_name" {
  command = apply               # use 'apply' to get mock values on computed attrs

  variables {
    # supply the minimum required variables for your module
    name_prefix = "test"
    ...
  }

  assert {
    condition     = <expression that must be true>
    error_message = "Human-readable explanation of what failed"
  }
}
```

### What to assert on

| Test goal             | Example assertion                                                  |
| --------------------- | ------------------------------------------------------------------ |
| Resource created      | `length(hcs_vpc.this) == 1`                                        |
| Resource NOT created  | `length(hcs_nat_gateway.this) == 0`                                |
| Naming convention     | `hcs_vpc.this.name == "${var.name_prefix}-vpc"`                    |
| for_each count        | `length(hcs_vpc_subnet.public) == length(var.public_subnet_cidrs)` |
| Conditional config    | `hcs_obs_bucket.this["x"].versioning == true`                      |
| Output present        | `output.bucket_ids != {}`                                          |
| Default value applied | `hcs_obs_bucket.this["x"].acl == "private"`                        |

### Adding a data source override

Required when the module accesses list elements from a data source (e.g. `images[0].id`):

```hcl
mock_provider "hcs" {
  mock_data "hcs_ims_images" {
    defaults = {
      images = [{ id = "mock-img-id", name = "Ubuntu 22.04 server 64bit" }]
    }
  }
}
```

### Adding an integration test file

```hcl
# modules/network/tests/integration.tftest.hcl
# Requires: TF_VAR_access_key and TF_VAR_secret_key

provider "hcs" {
  region       = "MTN_Cloud"
  domain_name  = "IT-DEPT"
  project_name = "lagos-mtn-1_A_and_E"
  access_key   = var.access_key
  secret_key   = var.secret_key
  auth_url     = var.hcs_auth_url
  insecure     = true
  endpoints    = var.endpoints
}

variable "access_key"   { type = string; sensitive = true }
variable "secret_key"   { type = string; sensitive = true }
variable "hcs_auth_url" { type = string; default = "" }
variable "endpoints"    { type = map(string); default = {} }

run "real_provider_plan" {
  command = plan    # ← ALWAYS use plan in integration tests to avoid creating resources

  variables {
    name_prefix        = "inttest"
    vpc_cidr           = "10.99.0.0/16"
    availability_zones = ["az1.dc0"]
    ...
  }

  assert {
    condition     = hcs_vpc.this.cidr == "10.99.0.0/16"
    error_message = "VPC CIDR must match"
  }
}
```

---

## CI/CD Integration

### GitHub Actions example

```yaml
name: Terraform Module Tests

on:
  pull_request:
    paths:
      - "modules/**"
      - "environments/**"

jobs:
  static:
    name: Static Analysis
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"

      - name: Static checks — all modules
        run: ./scripts/test-module.sh --all --level static

  unit:
    name: Unit Tests
    runs-on: ubuntu-latest
    needs: static
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"

      - name: Unit tests — all modules
        run: ./scripts/test-module.sh --all --level unit

  integration:
    name: Integration Tests
    runs-on: ubuntu-latest
    needs: unit
    # Only run on main branch pushes (not on every PR)
    if: github.ref == 'refs/heads/main'
    environment: hcs-integration
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"

      - name: Integration tests — network + security
        env:
          TF_VAR_access_key: ${{ secrets.HCS_ACCESS_KEY }}
          TF_VAR_secret_key: ${{ secrets.HCS_SECRET_KEY }}
        run: |
          ./scripts/test-module.sh network --level integration
          ./scripts/test-module.sh security --level integration
```

### GitLab CI example

```yaml
stages:
  - static
  - unit
  - integration

terraform:static:
  stage: static
  image: hashicorp/terraform:1.9
  script:
    - ./scripts/test-module.sh --all --level static

terraform:unit:
  stage: unit
  image: hashicorp/terraform:1.9
  script:
    - ./scripts/test-module.sh --all --level unit

terraform:integration:
  stage: integration
  image: hashicorp/terraform:1.9
  only:
    - main
  variables:
    TF_VAR_access_key: $HCS_ACCESS_KEY
    TF_VAR_secret_key: $HCS_SECRET_KEY
  script:
    - ./scripts/test-module.sh network --level integration
```

---

## Troubleshooting

### `Error: The argument "mock_provider" is not expected.`

You are on Terraform < 1.6. Upgrade to 1.6 or later.

```bash
terraform version
# must show >= 1.6.0
```

### `Error: Unsupported argument "mock_data"`

`mock_data` blocks inside `mock_provider` require Terraform **1.7+**. Either upgrade, or remove the `mock_data` override and ensure your module handles the mock provider's auto-generated values without indexing into lists.

### `terraform test` exits 0 but no tests ran

Check that your test files are named `*.tftest.hcl` (not `.tf`) and are inside the module directory or its `tests/` subdirectory.

### `Error: Failed to install provider` during `terraform init`

The HCS provider (`huaweicloud/hcs`) must be reachable from the Terraform registry. If running in an air-gapped environment, configure a [network mirror](https://developer.hashicorp.com/terraform/cli/config/config-file#provider-installation) pointing at your internal Artifactory/Nexus. Example `~/.terraformrc`:

```hcl
provider_installation {
  network_mirror {
    url = "https://your-nexus.internal/terraform-mirror/"
  }
}
```

### Integration test fails with `401 Unauthorized`

Confirm credentials are exported correctly:

```bash
echo "AK length: ${#TF_VAR_access_key}"
echo "SK length: ${#TF_VAR_secret_key}"
```

Both must be non-zero. Check that `hcs_auth_url` and `endpoints` in your `terraform.tfvars` point to the correct HCS API gateway.

### `terraform test` hangs on a `command = apply` run

With `mock_provider`, apply should be near-instant. Hanging usually means a real provider is being invoked instead of the mock. Verify the `mock_provider "hcs" {}` block is at the top of the test file, outside any `run` block.

### State lock stuck after a failed apply

```bash
./scripts/tf.sh dev unlock <lock-id>
```

Find the lock ID in the error message or via:

```bash
./scripts/tf.sh dev state list
```

---

## Summary: Which Command for Which Task

| Task                                    | Command                                                 |
| --------------------------------------- | ------------------------------------------------------- |
| Check module formatting                 | `./scripts/test-module.sh <module> --level static`      |
| Run unit tests for one module           | `./scripts/test-module.sh <module> --level unit`        |
| Run all unit tests                      | `./scripts/test-module.sh --all --level unit`           |
| Validate with real provider (plan only) | `./scripts/test-module.sh <module> --level integration` |
| Set up a new environment interactively  | `./scripts/setup-environment.sh <env>`                  |
| Initialise an environment               | `./scripts/tf.sh <env> init`                            |
| Preview all changes in an environment   | `./scripts/tf.sh <env> plan`                            |
| Preview changes for one module only     | `./scripts/tf.sh <env> plan -- -target=module.<name>`   |
| Deploy all changes                      | `./scripts/tf.sh <env> apply`                           |
| Deploy one module only                  | `./scripts/tf.sh <env> apply -- -target=module.<name>`  |
| Destroy an environment                  | `./scripts/tf.sh <env> destroy`                         |
| Inspect state                           | `./scripts/tf.sh <env> state list`                      |
| Debug Terraform expressions live        | `./scripts/tf.sh <env> console`                         |
