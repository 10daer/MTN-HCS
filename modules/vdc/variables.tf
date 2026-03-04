###############################################################################
# Module: vdc – Input Variables
#
# Flexible maps let the calling environment define exactly which users,
# groups, roles, projects, memberships, and role-assignments to manage.
###############################################################################

# ─────────────────────────────────────────────
# Core
# ─────────────────────────────────────────────
variable "vdc_id" {
  description = "VDC ID (1-36 chars, lowercase letters/digits/hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,36}$", var.vdc_id))
    error_message = "vdc_id must be 1-36 chars: lowercase letters, digits, hyphens."
  }
}

variable "domain_id" {
  description = "Tenant (domain) ID — required for tenant-level role assignments."
  type        = string
  default     = ""
}

variable "region_id" {
  description = "Region identifier (e.g. cn-north-1). Used as reference; not consumed by resources directly."
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────
# Users
# ─────────────────────────────────────────────
variable "users" {
  description = <<-EOT
    Map of VDC users to create. Key = logical name used for cross-references.

    Fields:
      name         – (Required) Username, 4-32 chars.
      password     – (Optional) Required for LOCAL_AUTH / MACHINE_USER.
      display_name – (Optional) Alias, 0-128 chars.
      auth_type    – (Optional) LOCAL_AUTH | SAML_AUTH | LDAP_AUTH | MACHINE_USER. Default: LOCAL_AUTH.
      enabled      – (Optional) true/false. Default: true.
      description  – (Optional) Max 255 chars.
      access_mode  – (Optional) default | console | programmatic. Default: default.
  EOT
  type = map(object({
    name         = string
    password     = optional(string)
    display_name = optional(string)
    auth_type    = optional(string, "LOCAL_AUTH")
    enabled      = optional(bool, true)
    description  = optional(string)
    access_mode  = optional(string, "default")
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, u in var.users :
      can(regex("^[a-zA-Z0-9@._-]{4,32}$", u.name))
    ])
    error_message = "Each user name must be 4-32 chars (letters, digits, @, ., _, -)."
  }

  validation {
    condition = alltrue([
      for k, u in var.users :
      contains(["LOCAL_AUTH", "SAML_AUTH", "LDAP_AUTH", "MACHINE_USER"], u.auth_type)
    ])
    error_message = "auth_type must be one of: LOCAL_AUTH, SAML_AUTH, LDAP_AUTH, MACHINE_USER."
  }

  validation {
    condition = alltrue([
      for k, u in var.users :
      contains(["default", "console", "programmatic"], u.access_mode)
    ])
    error_message = "access_mode must be one of: default, console, programmatic."
  }

  validation {
    condition = alltrue([
      for k, u in var.users :
      u.auth_type != "MACHINE_USER" || u.access_mode == "programmatic"
    ])
    error_message = "MACHINE_USER auth_type requires access_mode = 'programmatic'."
  }
}

# ─────────────────────────────────────────────
# Groups
# ─────────────────────────────────────────────
variable "groups" {
  description = <<-EOT
    Map of VDC user groups to create. Key = logical name for cross-references.

    Fields:
      name        – (Required) 1-64 chars, letters/digits/-/_.
      description – (Optional) Max 255 chars.
  EOT
  type = map(object({
    name        = string
    description = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, g in var.groups :
      can(regex("^[a-zA-Z_][a-zA-Z0-9_-]{0,63}$", g.name))
    ])
    error_message = "Group name must be 1-64 chars (letters, digits, -, _) and cannot start with a digit."
  }
}

# ─────────────────────────────────────────────
# Roles (custom)
# ─────────────────────────────────────────────
variable "roles" {
  description = <<-EOT
    Map of custom VDC roles to create.

    Fields:
      name        – (Required) Role name.
      description – (Optional) Role description.
      type        – (Optional) AX (Global) or XA (Regional). Default: XA.
      policy      – (Required) JSON policy document (Version 1.1).
  EOT
  type = map(object({
    name        = string
    description = optional(string)
    type        = optional(string, "XA")
    policy      = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, r in var.roles :
      contains(["AX", "XA"], r.type)
    ])
    error_message = "Role type must be AX (Global) or XA (Regional)."
  }
}

# ─────────────────────────────────────────────
# Projects (Resource Spaces)
# ─────────────────────────────────────────────
variable "projects" {
  description = <<-EOT
    Map of VDC projects (resource spaces) to create.

    Fields:
      name         – (Required) Must start with "{region_id}_". 1-64 chars.
      display_name – (Optional) Friendly name, 0-64 chars.
      description  – (Optional) Max 255 chars.
  EOT
  type = map(object({
    name         = string
    display_name = optional(string)
    description  = optional(string)
  }))
  default = {}
}

# ─────────────────────────────────────────────
# Group Memberships
# ─────────────────────────────────────────────
variable "group_memberships" {
  description = <<-EOT
    Map of group → user memberships.

    Fields:
      group_key – Key from var.groups (managed) or "existing:<key>" for data-source group.
      user_keys – List of keys from var.users (managed) or "existing:<key>" for data-source users.
  EOT
  type = map(object({
    group_key = string
    user_keys = list(string)
  }))
  default = {}
}

# ─────────────────────────────────────────────
# Group Role Assignments
# ─────────────────────────────────────────────
variable "group_role_assignments" {
  description = <<-EOT
    Map of role assignments per group.

    Fields:
      group_key   – Key from var.groups or "existing:<key>".
      assignments – List of assignment blocks:
        role_key              – Key from var.roles or "existing:<key>".
        domain_id             – (Optional) Tenant ID for tenant-scope.
        project_key           – (Optional) Key from var.projects or "all".
        project_id            – (Optional) Explicit project ID (use project_key instead when possible).
        enterprise_project_id – (Optional) Enterprise project ID.

    Constraint: Only ONE of domain_id (alone), project_key/project_id, or enterprise_project_id may be set per assignment.
  EOT
  type = map(object({
    group_key = string
    assignments = list(object({
      role_key              = string
      domain_id             = optional(string)
      project_key           = optional(string)
      project_id            = optional(string)
      enterprise_project_id = optional(string)
    }))
  }))
  default = {}
}

# ─────────────────────────────────────────────
# Data Source Lookups — existing resources
# ─────────────────────────────────────────────
variable "existing_roles" {
  description = <<-EOT
    Map of existing roles to look up via data source.
    Key = logical reference name. Provide display_name or name.
  EOT
  type = map(object({
    display_name = optional(string)
    name         = optional(string)
  }))
  default = {}
}

variable "existing_groups" {
  description = <<-EOT
    Map of existing groups to look up via data source.
    Key = logical reference name. Provide group name.
  EOT
  type = map(object({
    name = string
  }))
  default = {}
}

variable "existing_users" {
  description = <<-EOT
    Map of existing users to look up via data source.
    Key = logical reference name. Provide username.
  EOT
  type = map(object({
    name = string
  }))
  default = {}
}
