###############################################################################
# Unit tests: security module
#
# Uses mock_provider — no HCS credentials required.
# Run:
#   cd modules/security && terraform test
#   ./scripts/test-module.sh security --level unit
###############################################################################

mock_provider "hcs" {}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1: Empty security_groups map creates nothing
# ─────────────────────────────────────────────────────────────────────────────
run "empty_security_groups" {
  command = apply

  variables {
    name_prefix     = "test-dev"
    security_groups = {}
  }

  assert {
    condition     = length(hcs_networking_secgroup.this) == 0
    error_message = "No security groups should be created when the map is empty"
  }

  assert {
    condition     = output.security_group_ids == {}
    error_message = "security_group_ids output must be empty map"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: Security groups are created with correct naming
# ─────────────────────────────────────────────────────────────────────────────
run "security_groups_named_correctly" {
  command = apply

  variables {
    name_prefix = "myapp-dev"
    security_groups = {
      web = { description = "Web tier" }
      app = { description = "App tier" }
    }
  }

  assert {
    condition     = length(hcs_networking_secgroup.this) == 2
    error_message = "Two security groups should be created"
  }

  assert {
    condition     = hcs_networking_secgroup.this["web"].name == "myapp-dev-web-sg"
    error_message = "Web SG name must be '<name_prefix>-web-sg'"
  }

  assert {
    condition     = hcs_networking_secgroup.this["app"].name == "myapp-dev-app-sg"
    error_message = "App SG name must be '<name_prefix>-app-sg'"
  }

  assert {
    condition     = length(output.security_group_ids) == 2
    error_message = "security_group_ids must have two entries"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: Default egress rule is created for every security group
# ─────────────────────────────────────────────────────────────────────────────
run "default_egress_rule_per_group" {
  command = apply

  variables {
    name_prefix = "test"
    security_groups = {
      web = {}
      db  = {}
    }
  }

  assert {
    condition     = length(hcs_networking_secgroup_rule.default_egress) == 2
    error_message = "Each SG must have exactly one default egress rule"
  }

  assert {
    condition     = hcs_networking_secgroup_rule.default_egress["web"].direction == "egress"
    error_message = "Default rule must be egress direction"
  }

  assert {
    condition     = hcs_networking_secgroup_rule.default_egress["web"].remote_ip_prefix == "0.0.0.0/0"
    error_message = "Default egress must allow all destinations"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4: Ingress rules are built from the security_groups map
# ─────────────────────────────────────────────────────────────────────────────
run "ingress_rules_created" {
  command = apply

  variables {
    name_prefix = "test"
    security_groups = {
      web = {
        description = "Web tier"
        ingress_rules = [
          { protocol = "tcp", port_min = 80, port_max = 80, cidr = "0.0.0.0/0", description = "HTTP" },
          { protocol = "tcp", port_min = 443, port_max = 443, cidr = "0.0.0.0/0", description = "HTTPS" }
        ]
      }
    }
  }

  assert {
    condition     = length(hcs_networking_secgroup_rule.ingress) == 2
    error_message = "Two ingress rules should be created for the web SG"
  }

  assert {
    condition     = hcs_networking_secgroup_rule.ingress["web-ingress-0"].port_range_min == 80
    error_message = "First ingress rule must have port_range_min = 80"
  }

  assert {
    condition     = hcs_networking_secgroup_rule.ingress["web-ingress-0"].direction == "ingress"
    error_message = "Ingress rule direction must be 'ingress'"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 5: Multiple security groups, each with their own ingress rules
# ─────────────────────────────────────────────────────────────────────────────
run "multi_tier_ingress" {
  command = apply

  variables {
    name_prefix = "test"
    security_groups = {
      web = {
        ingress_rules = [
          { protocol = "tcp", port_min = 443, port_max = 443, cidr = "0.0.0.0/0" }
        ]
      }
      app = {
        ingress_rules = [
          { protocol = "tcp", port_min = 8080, port_max = 8080, remote_sg_key = "web" }
        ]
      }
      db = {
        ingress_rules = [
          { protocol = "tcp", port_min = 5432, port_max = 5432, remote_sg_key = "app" }
        ]
      }
    }
  }

  assert {
    condition     = length(hcs_networking_secgroup.this) == 3
    error_message = "Three security groups should be created"
  }

  assert {
    condition     = length(hcs_networking_secgroup_rule.ingress) == 3
    error_message = "Three ingress rules total (one per tier)"
  }
}
