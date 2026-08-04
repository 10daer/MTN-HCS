###############################################################################
# VDC — users, groups, custom roles, projects, memberships, role assignments
# Module: ../../modules/vdc            Values: vdc.auto.tfvars
#
# This is HCS's identity layer — the reason modules/iam is an empty stub (the
# hcs provider exposes no IAM resources at all).
#
# Gated on vdc_id being set: the module requires a valid VDC id (1-36 chars,
# lowercase/digits/hyphens) and rejects an empty string, so leaving vdc_id = ""
# in vdc.auto.tfvars keeps the whole stack switched off.
###############################################################################

module "vdc" {
  count  = var.vdc_id != "" ? 1 : 0
  source = "../../modules/vdc"

  vdc_id    = var.vdc_id
  domain_id = var.domain_id
  region_id = var.region

  users    = var.vdc_users
  groups   = var.vdc_groups
  roles    = var.vdc_roles
  projects = var.vdc_projects

  group_memberships      = var.vdc_group_memberships
  group_role_assignments = var.vdc_group_role_assignments

  # Data-source lookups, referenced as "existing:<key>" in the maps above
  existing_roles  = var.vdc_existing_roles
  existing_groups = var.vdc_existing_groups
  existing_users  = var.vdc_existing_users
}
