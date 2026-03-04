###############################################################################
# Module: vdc – Outputs
###############################################################################

# ── Users ────────────────────────────────────
output "user_ids" {
  description = "Map of user keys to their IDs."
  value       = { for k, v in hcs_vdc_user.this : k => v.id }
}

output "user_names" {
  description = "Map of user keys to their usernames."
  value       = { for k, v in hcs_vdc_user.this : k => v.name }
}

# ── Groups ───────────────────────────────────
output "group_ids" {
  description = "Map of group keys to their IDs."
  value       = { for k, v in hcs_vdc_group.this : k => v.id }
}

output "group_names" {
  description = "Map of group keys to their names."
  value       = { for k, v in hcs_vdc_group.this : k => v.name }
}

# ── Roles ────────────────────────────────────
output "role_ids" {
  description = "Map of role keys to their IDs."
  value       = { for k, v in hcs_vdc_role.this : k => v.id }
}

output "role_names" {
  description = "Map of role keys to their names."
  value       = { for k, v in hcs_vdc_role.this : k => v.name }
}

# ── Projects (Resource Spaces) ───────────────
output "project_ids" {
  description = "Map of project keys to their IDs."
  value       = { for k, v in hcs_vdc_project.this : k => v.id }
}

output "project_names" {
  description = "Map of project keys to their names."
  value       = { for k, v in hcs_vdc_project.this : k => v.name }
}

output "project_regions" {
  description = "Map of project keys to their region lists."
  value       = { for k, v in hcs_vdc_project.this : k => v.regions }
}

# ── Memberships ──────────────────────────────
output "membership_ids" {
  description = "Map of membership keys to their IDs (group IDs)."
  value       = { for k, v in hcs_vdc_group_membership.this : k => v.id }
}

# ── Role Assignments ─────────────────────────
output "role_assignment_ids" {
  description = "Map of role-assignment keys to their IDs."
  value       = { for k, v in hcs_vdc_group_role_assignment.this : k => v.id }
}

# ── Resolved ID Maps (for downstream modules) ─
output "all_user_ids" {
  description = "Merged map of managed + existing user IDs."
  value       = local.resolved_user_ids
}

output "all_group_ids" {
  description = "Merged map of managed + existing group IDs."
  value       = local.resolved_group_ids
}

output "all_role_ids" {
  description = "Merged map of managed + existing role IDs."
  value       = local.resolved_role_ids
}

output "all_project_ids" {
  description = "Merged map of managed + 'all' project IDs."
  value       = local.resolved_project_ids
}
