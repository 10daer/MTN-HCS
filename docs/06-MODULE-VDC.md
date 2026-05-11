# Module Deployment: VDC (Identity & Access Management)
## `modules/vdc`

> **Prerequisites**: [00-SETUP.md](00-SETUP.md) complete. VDC has **no dependency** on Network or Security.
> **Deploy order**: **Any time** — VDC is the identity layer and is independent of all other modules. In `dev/main.tf` it is deployed first (position 0 in the chain).
> **Estimated apply time**: ~2 minutes

---

## What This Module Creates

VDC (Virtual Data Center) is HCS's tenant-level identity system. It is separate from the global IAM — VDC manages users, groups, and roles **within your HCS tenant**.

| Resource | HCS Type | Description |
|---|---|---|
| Custom roles | `hcs_vdc_role` | JSON-policy-based roles for granular permission control |
| Projects | `hcs_vdc_project` | Resource spaces (namespaces) within the tenant |
| Users | `hcs_vdc_user` | Individual user accounts (human or machine) |
| Groups | `hcs_vdc_group` | Logical collections of users |
| Group memberships | `hcs_vdc_group_membership` | Assigns users to groups |
| Role assignments | `hcs_vdc_group_role_assignment` | Grants groups access at tenant, project, or enterprise project scope |

### Role assignment scopes

| Scope | When to use | How to configure |
|---|---|---|
| **Tenant (domain)** | Group needs access to all resources in the tenant | Set `domain_id` in the assignment |
| **Project** | Group needs access only within a specific resource space | Set `project_key` or `project_id` |
| **Enterprise project** | Group needs access to an enterprise project (if enabled) | Set `enterprise_project_id` |

---

## Step 1 — Gather Required IDs

Before writing tfvars, collect two IDs from the HCS console:

**VDC ID**:
1. HCS Console → My Credentials (top-right account menu)
2. Look for **Account ID** or **Tenant ID** — this is your `vdc_id`
3. Alternatively: Settings → Basic Information

**Domain ID**:
1. Same page as above — the **Domain ID** (sometimes shown as IAM Domain ID)
2. Required for tenant-scope role assignments

---

## Step 2 — Add VDC Values to `terraform.tfvars`

```hcl
# ── VDC — Identity & Access Management ───────────────────────────────────────
vdc_id    = "abc123def456"          # your HCS Account/Tenant ID
domain_id = "xyz789..."             # your HCS Domain ID (for role assignments)

# ── Look up built-in system roles (no creation, just data source lookup) ─────
# These are HCS pre-defined roles you want to assign to groups.
# The key is a logical name; display_name must match exactly in HCS console.
# Go to: HCS Console → IAM → Permissions → Roles & Policies for exact names.
vdc_existing_roles = {
  tenant_admin = { display_name = "Tenant Administrator" }
  tenant_guest = { display_name = "Tenant Guest" }
  ecs_admin    = { display_name = "ECS Administrator" }
  obs_operator = { display_name = "OBS Buckets Viewer" }
}

# ── Custom roles (JSON policy) ────────────────────────────────────────────────
vdc_roles = {
  ecs_operator = {
    name        = "ecs_operator"
    description = "Start, stop and list ECS instances — no create/delete"
    type        = "XA"            # XA = regional; AX = global
    policy      = <<-EOF
      {
        "Depends": [],
        "Statement": [
          {
            "Action": [
              "ecs:cloudServers:list",
              "ecs:cloudServers:start",
              "ecs:cloudServers:stop",
              "ecs:cloudServers:reboot"
            ],
            "Effect": "Allow"
          }
        ],
        "Version": "1.1"
      }
    EOF
  }
}

# ── Projects (resource spaces) ────────────────────────────────────────────────
# Name must be formatted as "<region_id>_<project_name>"
# Check your region ID in HCS Console → My Credentials → Projects
vdc_projects = {
  dev = {
    name         = "MTN_Cloud_dev"         # "<region>_<name>"
    display_name = "Development Environment"
    description  = "Dev resource space for myapp"
  }
}

# ── Users ─────────────────────────────────────────────────────────────────────
# Passwords: DO NOT put them here.
# Set via environment variables before running apply:
#   export TF_VAR_vdc_users='{ dev_admin = { name = "dev_admin", ... password = "MyP@ss123" } }'
vdc_users = {
  dev_admin = {
    name         = "dev_admin"
    display_name = "Dev Environment Admin"
    description  = "Primary dev environment administrator"
    auth_type    = "LOCAL_AUTH"      # LOCAL_AUTH | FEDERATION_AUTH
    access_mode  = "default"         # default = console + API
    enabled      = true
    # password set via TF_VAR_vdc_users env var
  }
  ci_bot = {
    name        = "ci_service_bot"
    description = "CI/CD pipeline service account"
    auth_type   = "MACHINE_USER"     # machine user = no console login
    access_mode = "programmatic"     # programmatic = API only
    enabled     = true
  }
}

# ── Groups ────────────────────────────────────────────────────────────────────
vdc_groups = {
  developers = {
    name        = "Developers"
    description = "Development team members"
  }
  ops = {
    name        = "Operations"
    description = "SRE and operations team"
  }
  ci_runners = {
    name        = "CI Runners"
    description = "Service accounts for CI/CD pipelines"
  }
}

# ── Group Memberships ─────────────────────────────────────────────────────────
vdc_group_memberships = {
  dev_members = {
    group_key = "developers"
    user_keys = ["dev_admin"]         # list of keys from vdc_users above
  }
  ci_membership = {
    group_key = "ci_runners"
    user_keys = ["ci_bot"]
  }
}

# ── Role Assignments ──────────────────────────────────────────────────────────
vdc_group_role_assignments = {

  # Give developers ecs_operator access in the dev project
  dev_team_project_access = {
    group_key = "developers"
    assignments = [
      {
        role_key    = "ecs_operator"       # key from vdc_roles above
        project_key = "dev"                # key from vdc_projects above
      }
    ]
  }

  # Give ops team read-only access to the entire tenant
  ops_tenant_readonly = {
    group_key = "ops"
    assignments = [
      {
        role_key  = "existing:tenant_guest"   # "existing:" prefix = from vdc_existing_roles
        domain_id = "<your-domain-id>"        # same as domain_id variable above
      }
    ]
  }

  # Give CI runners ECS admin on the dev project
  ci_project_access = {
    group_key = "ci_runners"
    assignments = [
      {
        role_key    = "existing:ecs_admin"
        project_key = "dev"
      }
    ]
  }
}
```

### Setting user passwords safely

Never put passwords in `terraform.tfvars`. Use the environment variable override:

```bash
export TF_VAR_vdc_users='{
  dev_admin = {
    name        = "dev_admin"
    display_name = "Dev Admin"
    auth_type   = "LOCAL_AUTH"
    access_mode = "default"
    enabled     = true
    password    = "MySecureP@ss123"
  }
  ci_bot = {
    name        = "ci_service_bot"
    auth_type   = "MACHINE_USER"
    access_mode = "programmatic"
    enabled     = true
  }
}'
```

HCS password requirements: minimum 8 characters, must include uppercase, lowercase, digit, and special character.

---

## Step 3 — Plan the VDC Module

```bash
source ~/.hcs-credentials.sh

cd environments/dev
terraform plan \
  -var-file="terraform.tfvars" \
  -target=module.vdc \
  -out=vdc.tfplan
```

### What to verify in the plan output

```
# module.vdc.hcs_vdc_role.roles["ecs_operator"] will be created
  + name = "ecs_operator"
  + type = "XA"

# module.vdc.hcs_vdc_project.projects["dev"] will be created
  + name = "MTN_Cloud_dev"

# module.vdc.hcs_vdc_user.users["dev_admin"] will be created
  + name        = "dev_admin"
  + auth_type   = "LOCAL_AUTH"
  + access_mode = "default"

# module.vdc.hcs_vdc_group.groups["developers"] will be created
  + name = "Developers"

# module.vdc.hcs_vdc_group_membership.memberships["dev_members"] will be created
  + group_id = (known after apply)
  + user_ids = [ (known after apply) ]

# module.vdc.hcs_vdc_group_role_assignment.assignments["dev_team_project_access-0"] will be created
  + group_id   = (known after apply)
  + role_id    = (known after apply)
  + project_id = (known after apply)
```

Confirm:
- ✅ All users, groups, and roles you defined are being created
- ✅ Memberships reference the correct group and user keys
- ✅ Role assignments show the correct scope (project vs domain)
- ✅ `existing:` prefixed roles are not being created (they're lookups)

---

## Step 4 — Apply

```bash
terraform apply vdc.tfplan
```

Expected output:
```
module.vdc.hcs_vdc_role.roles["ecs_operator"]: Creating...
module.vdc.hcs_vdc_project.projects["dev"]: Creating...
module.vdc.hcs_vdc_user.users["dev_admin"]: Creating...
module.vdc.hcs_vdc_user.users["ci_bot"]: Creating...
...
module.vdc.hcs_vdc_group_membership.memberships["dev_members"]: Creating...
module.vdc.hcs_vdc_group_role_assignment.assignments["dev_team_project_access-0"]: Creating...
...

Apply complete! Resources: 12 added, 0 changed, 0 destroyed.
```

---

## Step 5 — Verify

### View outputs

```bash
cd environments/dev
terraform state list | grep module.vdc
```

The module exposes:
- `all_user_ids` — map of all user IDs (managed + existing)
- `all_group_ids` — map of all group IDs
- `all_role_ids` — map of all role IDs
- `all_project_ids` — map of all project IDs

```bash
terraform state show 'module.vdc.hcs_vdc_user.users["dev_admin"]' | grep ' id '
```

### Verify in HCS Console

1. **Users**: HCS Console → IAM → Users → find `dev_admin`, `ci_service_bot`
2. **Groups**: IAM → User Groups → find `Developers`, `Operations`, `CI Runners`
3. **Group membership**: Click `Developers` group → Members tab → `dev_admin` should be listed
4. **Role assignments**: Click `Developers` group → Permissions tab → `ecs_operator` should be listed for the dev project

---

## Referencing Existing Users and Groups

If users or groups already exist in HCS and you don't want Terraform to manage them (just reference them):

```hcl
vdc_existing_users = {
  shared_admin = { name = "shared_admin" }      # HCS user display name
}

vdc_existing_groups = {
  infra_team = { name = "Infrastructure Team" } # HCS group name
}
```

These are looked up via data sources and exposed in `all_user_ids["existing:shared_admin"]` and `all_group_ids["existing:infra_team"]`.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `vdc_id is required` | `vdc_id` not set in tfvars | Find it in HCS Console → My Credentials |
| `user already exists` | A user with this name exists in HCS | Import it with `terraform import` or use `vdc_existing_users` |
| `role not found` | `vdc_existing_roles` display_name doesn't match HCS exactly | Check HCS Console → IAM → Permissions for exact name |
| `password does not meet requirements` | HCS password policy not met | 8+ chars, uppercase, lowercase, number, special char |
| `project name format invalid` | Project name doesn't start with `<region_id>_` | Format: `MTN_Cloud_dev`, `lagos-mtn-1_staging` |
| `assignment already exists` | Role was already assigned outside Terraform | Import the assignment or remove it from console first |
