# MTN-HCS-IAC — Terraform Repository Review
## Implementation Status & Uniformity Analysis

> **Scope**: Full read of every `.tf` file, script, workflow, and doc in the repository.
> **Date**: May 2026 | **Provider**: `huaweicloud/hcs ~> 2.4.0` | **TF**: `>= 1.5.0`

---

## 1. Repository Architecture

The repo follows a **flat-root, per-environment pattern** — a single root module per environment that calls all service modules. The layout is clean and purposeful:

```
MTN-HCS-IAC/
├── modules/          # 10 reusable service modules
├── environments/
│   ├── dev/          # Only environment with actual files
│   ├── staging/      # Empty
│   └── prod/         # Empty
├── scripts/          # 4 operational shell scripts
├── docs/             # 8 planning/design docs
├── exempt/           # Legacy scratch config (separate concern)
└── .github/workflows/terraform.yml
```

---

## 2. What Has Been Implemented

### 2.1 Module Layer (`modules/`)

Ten modules are present. Nine are fully implemented; one is an intentional placeholder.

#### `modules/network` — Complete
Provisions the foundational network layer:
- **VPC** (`hcs_vpc`) with configurable CIDR
- **Public subnets** (`hcs_vpc_subnet`) — dynamic `for_each` over a list of CIDRs, round-robin across AZs
- **Private subnets** — same pattern as public
- **NAT Gateway** (`hcs_nat_gateway`) + EIP (`hcs_vpc_eip`) — conditionally created via `count = var.enable_nat_gateway ? 1 : 0`
- **SNAT rules** (`hcs_nat_snat_rule`) — one per private subnet, enabling outbound internet from private tier
- **Default Security Group** — baseline group with all-egress allowed and intra-VPC ingress; `delete_default_rules = true` enforces clean-slate rules

**Outputs**: `vpc_id`, `vpc_cidr`, `public_subnet_ids` (map), `public_subnet_id_list` (list), `private_subnet_ids`, `private_subnet_id_list`, `default_security_group_id`, `nat_gateway_id`, `nat_eip_address`

---

#### `modules/security` — Complete
Parameterized security group factory:
- Accepts a `map(object({ description, ingress_rules }))` — callers define groups and rules declaratively
- Creates one `hcs_networking_secgroup` per map key, all with `delete_default_rules = true`
- Creates a default egress-allow-all rule per group
- Flattens ingress rules using `locals` + `flatten()`, keyed as `{sg_key}-ingress-{idx}`
- Supports both CIDR-based rules and **remote security group** references (`remote_sg_key`) — enabling clean inter-tier rules (e.g., app-tier only from web-tier)

**Outputs**: `security_group_ids` (map), `security_groups` (full resource map)

---

#### `modules/ecs` — Complete, most feature-rich module
Manages the full ECS lifecycle:
- **Keypairs** (`hcs_ecs_compute_keypair`)
- **Server Groups** (`hcs_ecs_compute_server_group`) with policy validation
- **Instances** (`hcs_ecs_compute_instance`) — resolves image ID from three sources (explicit ID → per-instance name → module default), merges security groups, round-robin AZ fallback
- **Dynamic blocks** for: extra NICs, inline data disks, scheduler hints, tags
- **EIPs** auto-created for instances with `assign_eip = true`
- **Volume Attachments** (`hcs_ecs_compute_volume_attach`)
- **Interface Attachments** (`hcs_ecs_compute_interface_attach`)
- **Snapshots** (`hcs_ecs_compute_snapshot`)
- Three input **validations**: `eip_type` required when `assign_eip=true`, `power_action` enum check, `encrypt_cipher` enum check
- `lifecycle { ignore_changes = [user_data, image_id] }` prevents drift on immutable fields

**Outputs**: 15 outputs covering IDs, names, status, IPs, disks, groups, attachments

---

#### `modules/eip` — Complete
Standalone EIP and bandwidth management:
- **Shared Bandwidths** (`hcs_vpc_bandwidth`) — multi-EIP pools
- **Dedicated EIPs** (`hcs_vpc_eip`) with `share_type = "PER"`
- **Shared EIPs** (`hcs_vpc_eip`) with `share_type = "WHOLE"` attached to a bandwidth pool
- **Bandwidth Associations** (`hcs_vpc_bandwidth_associate`) — moves a dedicated EIP into a shared pool
- **EIP Associations** (`hcs_vpc_eip_associate`) — binds EIP to a port or fixed IP
- A `locals` block provides **unified resolution maps** (`resolved_bandwidth_ids`, `resolved_eip_ids`, `resolved_eip_addresses`) merging managed resources with externally injected IDs

**Outputs**: 14 outputs, including `all_eip_ids` and `all_eip_addresses` merged convenience maps

---

#### `modules/obs` — Complete, most complex module
Full OBS (Object Storage Service) lifecycle:
- **Buckets** (`hcs_obs_bucket`) with: ACL, storage class, versioning, force-destroy, quota, KMS encryption (SSE-KMS), parallel FS, custom domain names, logging (cross-bucket), static website, CORS rules, lifecycle rules — all via dynamic blocks
- **Bucket ACLs** (`hcs_obs_bucket_acl`) — fine-grained per owner/account/public/log-delivery permissions
- **Objects** (`hcs_obs_bucket_object`) — file or inline content upload
- **Object ACLs** (`hcs_obs_bucket_object_acl`)
- **Bucket Policies** (`hcs_obs_bucket_policy`) — standalone JSON policy documents
- Locals provide `bucket_names` (auto-prefixed), `resolved_bucket_ids` (managed + existing), `resolved_object_keys`
- Existing bucket lookup via `data "hcs_obs_buckets"`
- The `"existing:"` key prefix convention is consistently applied

**Outputs**: 10 outputs including `resolved_bucket_ids` for downstream module consumption

---

#### `modules/cce` — Complete
Cloud Container Engine (Kubernetes):
- **Cluster** (`hcs_cce_cluster`) — flavor, VPC, subnet, container network type/CIDR, service CIDR, kube-proxy mode, optional EIP for API server, multi-AZ HA flag
- **Storage cleanup** on destroy: `delete_evs`, `delete_obs`, `delete_sfs`, `delete_efs`, `delete_all` all toggled via a single `delete_storage_on_destroy` boolean
- **Node Pools** (`hcs_cce_node_pool`) — `for_each` over a map; supports autoscaling, node labels, Kubernetes taints, extended params (max_pods, pre/postinstall scripts), data volumes via dynamic block
- **Namespaces** (`hcs_cce_namespace`) — `for_each` with labels and annotations
- **Data source** `hcs_cce_nodes` queries cluster nodes after pool creation
- `lifecycle { ignore_changes = [cluster_version] }` prevents forced destroy on HCS auto-patching

**Outputs**: 11 outputs; `kube_config_raw` and `certificate_users` marked `sensitive = true`

---

#### `modules/gaussdb` — Complete
GaussDB OpenGauss (enterprise PostgreSQL):
- **Parameter Templates** (`hcs_gaussdb_opengauss_parameter_template`) — supports from-scratch and clone-from-existing; `lifecycle { ignore_changes }` prevents drift on cloned templates
- **Instances** (`hcs_gaussdb_opengauss_instance`) — supports distributed, centralized, hcs2–hcs7 solutions; configures `ha { mode, replication_mode, consistency, consistency_protocol }` block; optional datastore, backup strategy, KMS TDE encryption
- AZ resolution falls back to all discovered AZs sliced to `az_count` if not explicitly set
- Unified `resolved_template_ids` local merges managed + existing templates
- Extended timeouts: create `120m`, update `90m`, delete `45m`

**Outputs**: 13 outputs including HA config, volume, datastore, backup strategy, and endpoints

---

#### `modules/rds` — Complete
RDS MySQL and PostgreSQL:
- **Instances** (`hcs_rds_instance`) — `db { type, version, password, port }` block; `backup_strategy` and `parameters` via dynamic blocks; optional HA replication, SSL, param group, time zone
- **MySQL databases** + accounts + database privileges (read/write grant matrix)
- **PostgreSQL databases** + accounts + privileges (with schema-level grants) + plugins (`hcs_rds_pg_plugin`)
- **SQL Audit** (`hcs_rds_sql_audit`) — configurable retention and audit types
- `resolved_instance_ids` local merges managed + existing using the `"existing:"` prefix convention
- `lifecycle { ignore_changes = [db, param_group_id, availability_zone] }`

**Outputs**: 10 outputs including the `resolved_instance_ids` convenience map

---

#### `modules/vdc` — Complete
VDC-level identity and access management:
- **Custom Roles** (`hcs_vdc_role`) — with JSON policy strings and type (XA = Regional)
- **Projects / Resource Spaces** (`hcs_vdc_project`)
- **Users** (`hcs_vdc_user`) — auth type, access mode, enabled flag
- **Groups** (`hcs_vdc_group`)
- **Group Memberships** (`hcs_vdc_group_membership`) — maps group → list of user keys
- **Group Role Assignments** (`hcs_vdc_group_role_assignment`) — supports tenant, project, and enterprise-project scope; `"all"` keyword handled in `resolved_project_ids`
- Four `resolved_*` locals merge managed + existing with the `"existing:"` prefix convention
- Strict `depends_on` chains prevent race conditions on membership and assignment

**Outputs**: 10 outputs including all four `all_*` resolved maps for downstream use

---

#### `modules/iam` — Intentional Placeholder
A single-file module with a clear explanatory comment:
> *"The HCS provider does NOT include IAM resources. This module exists to preserve module structure for future expansion."*

---

### 2.2 Environment Layer (`environments/`)

Only `dev/` is populated. `staging/` and `prod/` are empty directories.

| File | Purpose |
|---|---|
| `main.tf` | Root orchestration — instantiates all 9 service modules in dependency order |
| `variables.tf` | 699 lines — declares every variable for all 9 modules, grouped by service |
| `provider.tf` | `hcs` provider config driven entirely by variables |
| `backend.tf` | S3-compatible OBS remote state backend |
| `backend.tf.example` | Template for gitignored `backend.tf` |
| `terraform.tfvars` | Real dev values (81 lines, partial) |
| `terraform.tfvars.example` | Exhaustive reference with every variable documented (15.9 KB) |

The `main.tf` orchestrates modules in this explicit dependency chain:
```
vdc → network → security → eip → web(ecs) → app(ecs) → obs → cce → gaussdb → rds
```

`depends_on` is correctly placed on every module that requires network or security to exist first.

---

### 2.3 Scripts Layer (`scripts/`)

| Script | Purpose |
|---|---|
| `tf.sh` (552 lines) | Full Terraform wrapper: `init`, `validate`, `fmt`, `plan`, `apply`, `destroy`, `output`, `state`, `refresh`, `console`, `unlock`, `workspace` |
| `setup-environment.sh` | One-time per-environment scaffold |
| `setup-credentials.sh` | Machine-level credential helper |
| `test-module.sh` | Unified module test runner (static, unit, integration levels) |

`tf.sh` is production-grade: coloured output, credential masking, `prod_guard()` requiring typed confirmation (`"yes-prod"`), destroy requiring the environment name to be retyped, 5-second abort window before destroy proceeds.

---

### 2.4 CI/CD Layer (`.github/workflows/terraform.yml`)

Three jobs, gated correctly:

| Job | Trigger | Action |
|---|---|---|
| `validate` | All PRs and pushes to `main` | `terraform fmt -check -recursive` + `terraform init -backend=false` + `terraform validate` |
| `plan-dev` | PRs to `main` | Full `terraform plan`, posts output as PR comment |
| `apply-dev` | Push to `main` (merge) | `terraform apply -auto-approve` with manual approval gate via GitHub Environments |

State backend config is written dynamically from GitHub Secrets in both plan and apply jobs.

**Gap**: Only `dev` plan/apply jobs exist. `staging` and `prod` jobs are absent.

---

### 2.5 Documentation (`docs/`)

| File | Content |
|---|---|
| `TESTING.md` | Full testing guide for static, unit, integration test levels |
| `ECS-PLAN.md` | ECS design decisions |
| `EIP-PLAN.md` | EIP / bandwidth design |
| `GUASS-DB-PLAN.md` | GaussDB design (**note**: filename has typo — `GUASS` vs `GAUSS`) |
| `OBS-PLAN.md` | OBS bucket design |
| `RDS-PLAN.md` | RDS design |
| `VDC-PLAN.md` | VDC identity design |
| `hcs-provider-setup.md` | HCS provider bootstrap guide |

---

### 2.6 `exempt/` Directory

This is a **legacy scratch configuration** — written during initial HCS provider exploration. It contains:
- Hardcoded credentials in variable `default` values
- Hardcoded passwords in outputs (`"Test@Password123"`)
- Non-modular, all-in-one flat style
- No remote state, no `backend.tf`

This file is architecturally inconsistent with the rest of the repo and contains **exposed secrets**.

---

## 3. Uniformity & Convention Analysis

### What Is Consistent Across All Modules

#### File Structure
Every completed module has exactly the same four files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`. No module deviates.

#### `versions.tf` — 100% Identical
Every module's `versions.tf` is byte-for-byte identical: `>= 1.5.0` + `huaweicloud/hcs ~> 2.4.0`.

#### Header Comments
Every `main.tf` opens with a `###...###` block listing what the module manages and which provider it uses. Consistent across all modules.

#### Section Dividers
All modules use the same in-file section separator style (`# ───...─── / # Section Name / # ───...───`). Consistent.

#### Output Header Comments
All `outputs.tf` files open with a module header comment and use `# ── Category ──` separators. Fully consistent.

#### `for_each` as the Primary Iteration Pattern
All modules exclusively use `for_each` (never `count`) for managing collections of resources. This is the correct and consistent approach — it enables stable resource addressing when items are added or removed.

#### `"existing:"` Key Prefix Convention
Five modules (VDC, GaussDB, RDS, OBS, EIP) implement the same pattern: data sources for pre-existing resources are keyed with `"existing:{key}"` in resolution locals. This enables callers to reference both managed and unmanaged resources using a single unified map. Uniform across all modules that need it.

#### Resolved IDs Pattern
Every module that manages cross-resource references exposes a `resolved_*` local and a corresponding `all_*` output. Clean, consistent interface contract.

#### Sensitive Markings
`sensitive = true` is correctly applied to `access_key`, `secret_key`, `kube_config_raw`, `certificate_users`, `mysql_accounts`, and `pg_accounts`.

#### `lifecycle` Blocks
All modules that benefit from them use `lifecycle { ignore_changes = [...] }` appropriately.

| Module | Ignores |
|---|---|
| ECS | `user_data`, `image_id` |
| CCE | `cluster_version` |
| GaussDB | `password`, `availability_zone` |
| RDS | `db`, `param_group_id`, `availability_zone` |
| OBS | `acl`, `force_destroy` |

#### Timeout Blocks
All async resources define explicit `timeouts { create, update, delete }`. Values are appropriate per resource type.

#### Naming Convention
Resources follow `"${var.name_prefix}-<descriptor>"` throughout. `name_prefix` is built in the environment's `locals` block as `"${var.project}-${var.environment}"`.

#### Tagging
All compute/storage resources receive `tags = local.common_tags` containing `Project`, `Environment`, `Owner`, `ManagedBy = "terraform"`, `Region`.

---

### Deviations & Inconsistencies

#### 1. Mixed `try()` vs `lookup()` for Optional Fields

Some modules use `try(each.value.field, default)` while others use `lookup(each.value, "field", default)`:
- **Uses `try()`**: ECS, EIP, CCE, VDC
- **Uses `lookup()`**: OBS, RDS, CCE node pools (mixed within the same module)

Both are functionally equivalent but the inconsistency indicates different authoring sessions.

**Recommendation**: Standardise on `try()` — it is the idiomatic modern Terraform approach for typed objects.

---

#### 2. Cross-Reference Comments Missing on Complex Environment Variables

For ECS and EIP, the env `variables.tf` includes: `"See modules/ecs/variables.tf for full schema."` For GaussDB and some RDS variables, this cross-reference is absent — creating a maintenance risk if module schemas drift.

**Recommendation**: Add `# Schema mirrors modules/gaussdb/variables.tf` on the GaussDB and RDS instance env variable declarations.

---

#### 3. `obs_buckets` and `rds_instances` Use `type = any` at Environment Level

While modules have fully typed variables, the environment-level declaration for these two is untyped:
```hcl
variable "obs_buckets"   { type = any; default = {} }
variable "rds_instances" { type = any; default = {} }
```
Other variables for the same modules (e.g., `rds_mysql_databases`) are fully typed. Inconsistent within the same file.

**Recommendation**: Type these fully, or at minimum use `type = map(any)` over bare `type = any`.

---

#### 4. `staging/` and `prod/` Environments Are Empty

The directory structure implies three environments, but only `dev` has any content. Staging and prod cannot be deployed and the CI/CD pipeline only covers dev.

**Recommendation**: Scaffold `staging/` and `prod/` with copies of `variables.tf`, `provider.tf`, `backend.tf.example`, and appropriately sized `terraform.tfvars.example` (HA CCE flavors, multi-AZ, larger instance flavors).

---

#### 5. `terraform.tfvars` Is Incomplete

The committed `dev/terraform.tfvars` (81 lines) only covers HCS connection, endpoints, naming, network, compute, and CCE. No values exist for RDS, GaussDB, VDC, or OBS — those modules create zero resources in dev by default.

**Recommendation**: Either extend with placeholder/example values, or add explicit section comments explaining the intent.

---

#### 6. `exempt/main.tf` Contains Hardcoded Secrets — CRITICAL

```hcl
variable "access_key" { default = "AMO4D9ZQ6TW8WOPJZS6E" }
variable "secret_key" { default = "b1fMdZKq1QyhOdLMe7RCp1H2SvJtMdItehEoXIo9" }
```
And outputs expose `password = "Test@Password123"`.

**Recommendation**: Rotate these credentials immediately. Delete or sanitise `exempt/main.tf` before any further distribution of this repository.

---

#### 7. Module Tests Directories Exist but Content Is Unverified

The README and `test-module.sh` reference `tests/unit.tftest.hcl` and `tests/integration.tftest.hcl` inside each module. The `tests/` subdirectories exist in all modules, but if they are empty, the entire testing infrastructure described in `docs/TESTING.md` cannot execute.

**Recommendation**: Verify and populate test files. Unit tests using `mock_provider` are a stated convention in the README.

---

#### 8. Two Values Hardcoded Inline in `dev/main.tf`

```hcl
nat_gateway_spec   = "1"    # small — sufficient for dev
nat_bandwidth_size = 10
```
These are inlined rather than driven by variables, unlike every other argument in the file.

**Recommendation**: Promote to variables `nat_gateway_spec` and `nat_bandwidth_size` with appropriate defaults.

---

#### 9. Network Module Creates a Security Group — Slight Concern Separation

The `network` module creates `hcs_networking_secgroup.default` (baseline SG), while `modules/security` creates tiered SGs. This splits SG management across two modules.

**Recommendation**: Document in both modules why the default SG lives in `network` (it needs `vpc_cidr` for the intra-VPC ingress rule). Acceptable by design, just needs clarity.

---

## 4. Summary Scorecard

| Dimension | Status | Notes |
|---|---|---|
| Module file structure | ✅ Uniform | All modules: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` |
| Provider version pinning | ✅ Uniform | `~> 2.4.0` in all `versions.tf` and `backend.tf` |
| `for_each` usage | ✅ Uniform | No `count` used for collections anywhere |
| Naming convention | ✅ Uniform | `name_prefix-descriptor` throughout |
| Tagging | ✅ Uniform | All compute/storage resources tagged |
| Output descriptions | ✅ Uniform | Every output has a `description` field |
| Sensitive markings | ✅ Uniform | Credentials and kubeconfig marked sensitive |
| `lifecycle` blocks | ✅ Uniform | All long-running resources have appropriate ignore rules |
| Timeout blocks | ✅ Uniform | All async resources define explicit timeouts |
| `"existing:"` pattern | ✅ Uniform | All modules needing it implement it identically |
| `try()` vs `lookup()` | ⚠️ Mixed | Inconsistent within and across modules |
| Environment coverage | ⚠️ Incomplete | Only `dev` is implemented; `staging`/`prod` are empty |
| `type = any` usage | ⚠️ Inconsistent | OBS and RDS instances typed loosely at env level |
| `terraform.tfvars` completeness | ⚠️ Partial | RDS, GaussDB, VDC, OBS sections absent |
| Module test files | ⚠️ Unverified | `tests/` dirs exist; file content not confirmed |
| `exempt/main.tf` secrets | ❌ Critical | Hardcoded AK/SK — must be rotated and file removed |
| CI/CD coverage | ⚠️ Dev-only | No staging/prod plan or apply jobs |

---

## 5. Recommendations (Priority Order)

| Priority | Action |
|---|---|
| 🔴 Critical | Rotate the credentials in `exempt/main.tf` and delete or sanitise that file |
| 🟠 High | Scaffold `environments/staging/` and `environments/prod/` with full variable and tfvars files |
| 🟠 High | Verify that `tests/unit.tftest.hcl` exists in all module `tests/` directories |
| 🟡 Medium | Standardise all optional field access on `try()` — replace `lookup()` in OBS and RDS modules |
| 🟡 Medium | Add environment-appropriate values (or explicit empty comments) to `dev/terraform.tfvars` for RDS, GaussDB, VDC, and OBS |
| 🟡 Medium | Add `staging` and `prod` CI/CD jobs in `terraform.yml` once those environments are scaffolded |
| 🟢 Low | Fix documentation filename typo: `GUASS-DB-PLAN.md` → `GAUSS-DB-PLAN.md` |
| 🟢 Low | Promote hardcoded `nat_gateway_spec` and `nat_bandwidth_size` in `dev/main.tf` to proper variables |
| 🟢 Low | Add cross-reference comments to `gaussdb_instances` and `rds_instances` env variables pointing to module schemas |
