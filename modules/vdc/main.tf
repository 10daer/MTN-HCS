###############################################################################
# Module: vdc
#
# Manages VDC-level IAM & resource-space resources on Huawei Cloud Stack:
#   - Users            (hcs_vdc_user)
#   - Groups           (hcs_vdc_group)
#   - Custom Roles     (hcs_vdc_role)
#   - Projects          (hcs_vdc_project)  — resource spaces
#   - Group Membership (hcs_vdc_group_membership)
#   - Group Role Assign (hcs_vdc_group_role_assignment)
#
# Provider: huaweicloud/hcs (Huawei Cloud Stack)
###############################################################################

# ─────────────────────────────────────────────
# Data Sources — look up existing roles / groups / users
# ─────────────────────────────────────────────
data "hcs_vdc_role" "existing" {
  for_each = var.existing_roles

  display_name = try(each.value.display_name, null)
  name         = try(each.value.name, null)
}

data "hcs_vdc_group" "existing" {
  for_each = var.existing_groups

  vdc_id = var.vdc_id
  name   = each.value.name
}

data "hcs_vdc_user" "existing" {
  for_each = var.existing_users

  vdc_id = var.vdc_id
  name   = each.value.name
}

# ─────────────────────────────────────────────
# 1. Custom Roles
# ─────────────────────────────────────────────
resource "hcs_vdc_role" "this" {
  for_each = var.roles

  name        = each.value.name
  description = try(each.value.description, null)
  type        = try(each.value.type, "XA") # XA = Regional (most common)
  policy      = each.value.policy
}

# ─────────────────────────────────────────────
# 2. Projects (Resource Spaces)
# ─────────────────────────────────────────────
resource "hcs_vdc_project" "this" {
  for_each = var.projects

  vdc_id       = var.vdc_id
  name         = each.value.name
  display_name = try(each.value.display_name, null)
  description  = try(each.value.description, null)
}

# ─────────────────────────────────────────────
# 3. Users
# ─────────────────────────────────────────────
resource "hcs_vdc_user" "this" {
  for_each = var.users

  vdc_id       = var.vdc_id
  name         = each.value.name
  password     = try(each.value.password, null)
  display_name = try(each.value.display_name, null)
  auth_type    = try(each.value.auth_type, "LOCAL_AUTH")
  enabled      = try(each.value.enabled, true)
  description  = try(each.value.description, null)
  access_mode  = try(each.value.access_mode, "default")
}

# ─────────────────────────────────────────────
# 4. Groups
# ─────────────────────────────────────────────
resource "hcs_vdc_group" "this" {
  for_each = var.groups

  vdc_id      = var.vdc_id
  name        = each.value.name
  description = try(each.value.description, null)
}

# ─────────────────────────────────────────────
# 5. Group Memberships
#
# Each membership maps a group key → list of user keys.
# User keys are resolved from hcs_vdc_user.this or
# data.hcs_vdc_user.existing, depending on the prefix.
# ─────────────────────────────────────────────
resource "hcs_vdc_group_membership" "this" {
  for_each = var.group_memberships

  group = local.resolved_group_ids[each.value.group_key]

  users = [
    for user_key in each.value.user_keys :
    local.resolved_user_ids[user_key]
  ]

  depends_on = [
    hcs_vdc_user.this,
    hcs_vdc_group.this,
  ]
}

# ─────────────────────────────────────────────
# 6. Group Role Assignments
#
# Assigns one or more roles to a group at the tenant,
# resource-space (project), or "all projects" scope.
# ─────────────────────────────────────────────
resource "hcs_vdc_group_role_assignment" "this" {
  for_each = var.group_role_assignments

  group_id = local.resolved_group_ids[each.value.group_key]

  dynamic "role_assignment" {
    for_each = each.value.assignments
    content {
      role_id               = local.resolved_role_ids[role_assignment.value.role_key]
      domain_id             = try(role_assignment.value.domain_id, null)
      project_id            = try(role_assignment.value.project_key, null) != null ? local.resolved_project_ids[role_assignment.value.project_key] : try(role_assignment.value.project_id, null)
      enterprise_project_id = try(role_assignment.value.enterprise_project_id, null)
    }
  }

  depends_on = [
    hcs_vdc_group.this,
    hcs_vdc_role.this,
    hcs_vdc_group_membership.this,
  ]
}

# ─────────────────────────────────────────────
# Locals — unified ID resolution
#
# Keys prefixed with "existing:" resolve from data sources.
# All other keys resolve from managed resources.
# ─────────────────────────────────────────────
locals {
  # Merge managed + existing user IDs into a single lookup map
  resolved_user_ids = merge(
    { for k, v in hcs_vdc_user.this : k => v.id },
    { for k, v in data.hcs_vdc_user.existing : "existing:${k}" => v.id },
  )

  # Merge managed + existing group IDs
  resolved_group_ids = merge(
    { for k, v in hcs_vdc_group.this : k => v.id },
    { for k, v in data.hcs_vdc_group.existing : "existing:${k}" => v.id },
  )

  # Merge managed + existing role IDs
  resolved_role_ids = merge(
    { for k, v in hcs_vdc_role.this : k => v.id },
    { for k, v in data.hcs_vdc_role.existing : "existing:${k}" => v.id },
  )

  # Project IDs — managed only (+ special "all" keyword)
  resolved_project_ids = merge(
    { for k, v in hcs_vdc_project.this : k => v.id },
    { "all" = "all" },
  )
}
