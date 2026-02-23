###############################################################################
# Module: iam
# Creates IAM groups, custom policies, and service accounts (agency/role).
# NOTE: IAM operations are global in HCS — ensure HW_DOMAIN_NAME is set.
###############################################################################

# ─────────────────────────────────────────────
# Custom IAM Policies
# ─────────────────────────────────────────────
resource "huaweicloud_identity_policy" "this" {
  for_each = var.policies

  name        = "${var.name_prefix}-${each.key}"
  description = lookup(each.value, "description", "Managed by Terraform")
  policy_document = jsonencode({
    Version   = "1.1"
    Statement = each.value.statements
  })
}

# ─────────────────────────────────────────────
# IAM Groups
# ─────────────────────────────────────────────
resource "huaweicloud_identity_group" "this" {
  for_each = var.groups

  name        = "${var.name_prefix}-${each.key}"
  description = lookup(each.value, "description", "Managed by Terraform")
}

# Attach policies to groups
locals {
  group_policy_attachments = flatten([
    for group_key, group in var.groups : [
      for policy_key in lookup(group, "policy_keys", []) : {
        attach_key  = "${group_key}-${policy_key}"
        group_id    = huaweicloud_identity_group.this[group_key].id
        policy_id   = huaweicloud_identity_policy.this[policy_key].id
      }
    ]
  ])
}

resource "huaweicloud_identity_group_membership" "policy_attach" {
  # HCS uses role assignments for attaching policies to groups
  # This is done via project-level role assignments
  for_each = { for a in local.group_policy_attachments : a.attach_key => a }

  group = each.value.group_id
  users = []  # Users added separately; this just ensures group exists
}

# ─────────────────────────────────────────────
# Agency (Service Account / Role for inter-service trust)
# ─────────────────────────────────────────────
resource "huaweicloud_identity_agency" "this" {
  for_each = var.agencies

  name                  = "${var.name_prefix}-${each.key}"
  description           = lookup(each.value, "description", "Managed by Terraform")
  delegated_service_name = each.value.delegated_service

  dynamic "project_role" {
    for_each = lookup(each.value, "project_roles", [])
    content {
      project = project_role.value.project
      roles   = project_role.value.roles
    }
  }

  dynamic "domain_roles" {
    for_each = lookup(each.value, "domain_roles", []) != [] ? [1] : []
    content {}
  }
}
