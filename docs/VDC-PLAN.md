````markdown
# Huawei Cloud Stack (HCS) VDC Terraform Context

**Purpose**  
This file is the complete reference context for any LLM (including yourself) when designing or generating Terraform configurations for Huawei Cloud Stack Virtual Data Center (VDC) IAM and resource-space management.  
Use this document to ensure all generated code follows the official resource schemas, best practices, naming conventions, constraints, and supported features exactly as documented.

---

## Supported Resources

### 1. hcs_vdc_user (Resource)

**Description:** Manages a VDC user within Huawei Cloud Stack.

**Example Usage**

```hcl
variable "vdc_id" {}
variable "user_password" {}

resource "hcs_vdc_user" "user01" {
  vdc_id       = var.vdc_id
  name         = "Username"
  password     = var.user_password
  display_name = "John Doe"
  auth_type    = "LOCAL_AUTH"
  enabled      = true
  description  = "Standard console user"
  access_mode  = "default"
}
```
````

**Argument Reference**

- `vdc_id` – (Required, String, ForceNew) VDC ID (1-36 chars, lowercase letters/digits/hyphens). Cannot be changed after creation.
- `name` – (Required, String, ForceNew) Username (4-32 chars). Allowed: letters, digits, @.\_-\. Cannot start with `op_svc`, `paas_op`, `\`; cannot be `admin`, `power_user`, `guest`. For LDAP_AD max 20 chars.
- `password` – (Optional, String) Required for `LOCAL_AUTH` and `MACHINE_USER`. Must contain ≥3 character types + special chars (except `< >`). 8-32 chars. Cannot contain username or reverse username.
- `display_name` – (Optional, String) Alias (0-128 chars). No `><`.
- `auth_type` – (Optional, String, ForceNew) `LOCAL_AUTH` (default), `SAML_AUTH`, `LDAP_AUTH`, `MACHINE_USER`.
  - `MACHINE_USER` requires `access_mode = "programmatic"`.
- `enabled` – (Optional, Boolean) `true` (default) / `false`.
- `description` – (Optional, String) 0-255 chars. No `><`.
- `access_mode` – (Optional, String) `default` (default), `console`, `programmatic`. `programmatic` forces `MACHINE_USER` and is immutable.

**Attributes Reference**

- `id` – User ID.

**Import**

```bash
terraform import hcs_vdc_user.example ed35bb2dada543d5977069780e98b2c3
```

---

### 2. hcs_vdc_group (Resource)

**Description:** Manages a VDC user group within Huawei Cloud Stack.

**Example Usage**

```hcl
variable "vdc_id" {}
variable "group_name" {}

resource "hcs_vdc_group" "group01" {
  vdc_id      = var.vdc_id
  name        = var.group_name
  description = "Finance team group"
}
```

**Argument Reference**

- `vdc_id` – (Required, String, ForceNew) Same rules as user.
- `name` – (Required, String) 1-64 chars. Letters, digits, `-`, `_`. Cannot start with digit or be `admin`, `power_user`, `guest`.
- `description` – (Optional, String) 0-255 chars. No `><`.

**Attributes Reference**

- `id` – User group ID.

**Import**

```bash
terraform import hcs_vdc_group.example 1ff4536fb0a44faba80450f9da0bf47a
```

---

### 3. hcs_vdc_role (Resource)

**NOTE:** Supported from ManageOne 8.6.0 onwards.

**Description:** Manages a VDC custom role.

**Example Usage**

```hcl
variable "role_name" {}

resource "hcs_vdc_role" "custom_role" {
  name        = var.role_name
  description = "Custom read-only role"
  type        = "AX"   # AX = Global, XA = Regional
  policy      = <<EOF
{
  "Depends": [],
  "Statement": [
    {
      "Action": ["ecs:cloudServers:list", "ecs:cloudServers:start"],
      "Effect": "Allow"
    }
  ],
  "Version": "1.1"
}
EOF
}
```

**Argument Reference**

- `name` – (Required, String) Role name.
- `description` – (Optional, String).
- `type` – (Optional, String, ForceNew) `AX` (Global services) or `XA` (Regional services).
- `policy` – (Required, String) JSON policy document.

**Attributes Reference**

- `id` – Role ID.

**Import**

```bash
terraform import hcs_vdc_role.example fa163eebcccbe1c10baa324fc930c75a
```

---

### 4. hcs_vdc_project (Resource)

**Description:** Manages a VDC resource space (project).

**Example Usage**

```hcl
variable "vdc_id" {}

resource "hcs_vdc_project" "prod" {
  vdc_id       = var.vdc_id
  name         = "cn-north-1_prod"
  display_name = "Production Environment"
  description  = "Main production resource space"
}
```

**Argument Reference**

- `vdc_id` – (Required, String) VDC ID.
- `name` – (Required, String) Must start with `{region_id}_`. Allowed: letters (case-insensitive), digits, `-`, `_`, `()`. 1-64 chars.
- `display_name` – (Optional, String) 0-64 chars. No `><`.
- `description` – (Optional, String) 0-255 chars. No `><`.

**Attributes Reference**

- `id` – Resource space ID.
- `regions` – List of regions.

**Import**

```bash
terraform import hcs_vdc_project.example 0350a018560a499692d972749fa6c94c
```

---

### 5. hcs_vdc_group_membership (Resource)

**NOTE:** Supported from ManageOne 8.5.1 onwards.

**Description:** Manages VDC user group membership.

**Example Usage**

```hcl
resource "hcs_vdc_group_membership" "finance_members" {
  group = hcs_vdc_group.finance.id
  users = [
    hcs_vdc_user.user01.id,
    hcs_vdc_user.user02.id
  ]
}
```

**Argument Reference**

- `group` – (Required, String, ForceNew) User group ID.
- `users` – (Required, Set) List of user IDs.

**Attributes Reference**

- `id` – User group ID (same as `group`).

**Import**

```bash
terraform import hcs_vdc_group_membership.example 3b002f5e4aae407082630a00d2ac0f40
```

---

### 6. hcs_vdc_group_role_assignment (Resource)

**NOTE:** Supported from ManageOne 8.5.1 onwards.

**Description:** Manages role assignments to a VDC user group (Tenant / Resource Space / Enterprise Project).

**Example Usage**

```hcl
resource "hcs_vdc_group_role_assignment" "tenant_admin" {
  group_id = hcs_vdc_group.finance.id

  role_assignment {
    domain_id = var.domain_id
    role_id   = hcs_vdc_role.admin_role.id
  }
}

resource "hcs_vdc_group_role_assignment" "project_read" {
  group_id = hcs_vdc_group.finance.id

  role_assignment {
    project_id = var.project_id
    role_id    = hcs_vdc_role.reader_role.id
  }
}

resource "hcs_vdc_group_role_assignment" "all_projects" {
  group_id = hcs_vdc_group.finance.id

  role_assignment {
    domain_id  = var.domain_id
    project_id = "all"
    role_id    = hcs_vdc_role.reader_role.id
  }
}
```

**Argument Reference**

- `group_id` – (Required, String, ForceNew) User group ID.
- `role_assignment` – (Required, Set, ForceNew) Block(s):
  - `role_id` – (Required, String, ForceNew)
  - `domain_id` – (Optional, String, ForceNew) Tenant ID
  - `project_id` – (Optional, String, ForceNew) Resource space ID or `"all"`
  - `enterprise_project_id` – (Optional, String, ForceNew)

**Important Note:** Only **one** of `domain_id`, `project_id`, or `enterprise_project_id` may be set. When `project_id = "all"`, `domain_id` is mandatory.

**Attributes Reference**

- `id` – User group ID.

**Import**

```bash
terraform import hcs_vdc_group_role_assignment.example 3b002f5e4aae407082630a00d2ac0f40
```

---

## Data Sources (for lookups / existing resources)

### hcs_vdc_group (Data Source)

```hcl
data "hcs_vdc_group" "finance" {
  vdc_id = var.vdc_id
  name   = "FinanceTeam"
}
```

**Attributes exported:** `id`, `domain_id`, `description`, `create_at`

### hcs_vdc_role (Data Source)

```hcl
data "hcs_vdc_role" "reader" {
  display_name = "Tenant Guest"   # preferred
  # or name = "te_agency" / "custom_xxx"
}
```

**Attributes exported:** `id`, `description`, `type`, `policy`, `catalog`

### hcs_vdc_user (Data Source)

```hcl
data "hcs_vdc_user" "admin" {
  vdc_id = var.vdc_id
  name   = "admin_user"
}
```

**Attributes exported:** `id`, `domain_id`, `display_name`, `enabled`, `description`, `ldap_id`, `create_at`, `auth_type`, `access_mode`, `top_vdc_id`

---

## Usage Guidelines for LLM Code Generation

1. Always declare variables for `vdc_id`, `domain_id`, `project_id`, passwords, etc.
2. Use `depends_on` when a resource depends on another (e.g., membership after group + users).
3. Prefer data sources when referencing existing groups/roles/users.
4. For role policies, always use valid JSON 1.1 format.
5. Never hard-code sensitive values – use variables or `var.*`.
6. Follow the exact argument constraints (length, allowed characters, ForceNew fields).
7. When assigning roles to "all projects" use `project_id = "all"` + mandatory `domain_id`.
8. For machine users (`MACHINE_USER`) always set `access_mode = "programmatic"`.

You now have the complete authoritative context.  
Generate Terraform code that strictly adheres to this schema.

```

**How to use this file**
Copy the entire content above into a file named `context.md` and attach/upload it to your chat with the LLM whenever you want to design HCS VDC Terraform solutions.

Would you like me to also create a companion `variables.tf` template or a full example module structure based on this context? Just say the word!
```
