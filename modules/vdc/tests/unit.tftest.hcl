###############################################################################
# Unit tests: vdc module
#
# Uses mock_provider — no HCS credentials required.
# Run:
#   cd modules/vdc && terraform test
#   ./scripts/test-module.sh vdc --level unit
###############################################################################

mock_provider "hcs" {
  mock_data "hcs_vdc_user" {
    defaults = { id = "mock-user-id", name = "existing-user" }
  }
  mock_data "hcs_vdc_group" {
    defaults = { id = "mock-group-id", name = "existing-group" }
  }
  mock_data "hcs_vdc_role" {
    defaults = { id = "mock-role-id", name = "existing-role" }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1: Empty configuration creates nothing
# ─────────────────────────────────────────────────────────────────────────────
run "empty_vdc_config" {
  command = apply

  variables {
    vdc_id = "mock-vdc-id"
  }

  assert {
    condition     = length(hcs_vdc_user.this) == 0
    error_message = "No users should be created with empty config"
  }

  assert {
    condition     = length(hcs_vdc_group.this) == 0
    error_message = "No groups should be created with empty config"
  }

  assert {
    condition     = length(hcs_vdc_role.this) == 0
    error_message = "No roles should be created with empty config"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: Users created with correct attributes
# ─────────────────────────────────────────────────────────────────────────────
run "users_created" {
  command = apply

  variables {
    vdc_id = "mock-vdc-id"
    users = {
      alice = { name = "alice", display_name = "Alice Smith", auth_type = "LOCAL_AUTH" }
      bob   = { name = "bob", display_name = "Bob Jones", auth_type = "LOCAL_AUTH" }
    }
  }

  assert {
    condition     = length(hcs_vdc_user.this) == 2
    error_message = "Two users should be created"
  }

  assert {
    condition     = hcs_vdc_user.this["alice"].name == "alice"
    error_message = "User alice name must match"
  }

  assert {
    condition     = length(output.user_ids) == 2
    error_message = "user_ids output must have two entries"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: Groups created with correct naming
# ─────────────────────────────────────────────────────────────────────────────
run "groups_created" {
  command = apply

  variables {
    vdc_id = "mock-vdc-id"
    groups = {
      admins  = { name = "admins", description = "Administrator group" }
      viewers = { name = "viewers", description = "Read-only access group" }
    }
  }

  assert {
    condition     = length(hcs_vdc_group.this) == 2
    error_message = "Two groups should be created"
  }

  assert {
    condition     = hcs_vdc_group.this["admins"].name == "admins"
    error_message = "admins group name must match"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4: Custom roles created
# ─────────────────────────────────────────────────────────────────────────────
run "custom_roles_created" {
  command = apply

  variables {
    vdc_id = "mock-vdc-id"
    roles = {
      readonly-role = {
        name        = "ReadOnlyRole"
        description = "Read-only access to all resources"
        type        = "XA"
        policy = jsonencode({
          Version = "1.1"
          Statement = [{
            Effect   = "Allow"
            Action   = ["*:*:Get*", "*:*:List*"]
            Resource = ["*"]
          }]
        })
      }
    }
  }

  assert {
    condition     = length(hcs_vdc_role.this) == 1
    error_message = "One custom role should be created"
  }

  assert {
    condition     = hcs_vdc_role.this["readonly-role"].name == "ReadOnlyRole"
    error_message = "Role name must match"
  }

  assert {
    condition     = length(output.role_ids) == 1
    error_message = "role_ids output must have one entry"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 5: Projects (resource spaces) created
# ─────────────────────────────────────────────────────────────────────────────
run "projects_created" {
  command = apply

  variables {
    vdc_id = "mock-vdc-id"
    projects = {
      dev-project  = { name = "region1_dev", display_name = "Development" }
      prod-project = { name = "region1_prod", display_name = "Production" }
    }
  }

  assert {
    condition     = length(hcs_vdc_project.this) == 2
    error_message = "Two projects should be created"
  }

  assert {
    condition     = length(output.project_ids) == 2
    error_message = "project_ids must have two entries"
  }
}
