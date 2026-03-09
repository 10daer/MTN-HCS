###############################################################################
# Unit tests: ecs module
#
# Uses mock_provider — no HCS credentials required.
# NOTE: The ECS module uses data sources (hcs_availability_zones, hcs_ims_images).
#       The mock_provider automatically returns synthetic values for these.
#       The mock 'images' list will contain at least one entry, so images[0].id
#       references are safe.
#
# Run:
#   cd modules/ecs && terraform test
#   ./scripts/test-module.sh ecs --level unit
###############################################################################

mock_provider "hcs" {
  # Override data sources that return lists to ensure at least one element exists
  mock_data "hcs_ims_images" {
    defaults = {
      images = [{ id = "mock-image-id-ubuntu", name = "Ubuntu 22.04 server 64bit" }]
    }
  }

  mock_data "hcs_availability_zones" {
    defaults = {
      names = ["az1.dc0", "az2.dc0"]
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1: Empty instances map creates no resources
# ─────────────────────────────────────────────────────────────────────────────
run "empty_instances" {
  command = apply

  variables {
    name_prefix = "test-dev"
    instances   = {}
  }

  assert {
    condition     = length(hcs_ecs_compute_instance.this) == 0
    error_message = "No ECS instances should be created when instances map is empty"
  }

  assert {
    condition     = output.instance_ids == {}
    error_message = "instance_ids output must be empty when no instances defined"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: Single instance is created with correct attributes
# ─────────────────────────────────────────────────────────────────────────────
run "single_instance_created" {
  command = apply

  variables {
    name_prefix            = "myapp-dev-web"
    default_key_pair       = "my-keypair"
    default_security_group_ids = ["sg-mock-id"]
    instances = {
      "web-01" = {
        flavor_id        = "c6.large.2"
        subnet_id        = "subnet-mock-id"
        system_disk_type = "business_type_01"
        system_disk_size = 40
      }
    }
  }

  assert {
    condition     = length(hcs_ecs_compute_instance.this) == 1
    error_message = "Exactly one ECS instance should be created"
  }

  assert {
    condition     = hcs_ecs_compute_instance.this["web-01"].flavor_id == "c6.large.2"
    error_message = "Instance flavor must match the supplied flavor_id"
  }

  assert {
    condition     = hcs_ecs_compute_instance.this["web-01"].system_disk_size == 40
    error_message = "System disk size must be 40"
  }

  assert {
    condition     = length(output.instance_ids) == 1
    error_message = "instance_ids output must contain one entry"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: Multiple instances via for_each
# ─────────────────────────────────────────────────────────────────────────────
run "multiple_instances" {
  command = apply

  variables {
    name_prefix      = "test"
    default_key_pair = "kp"
    default_security_group_ids = ["sg-001"]
    instances = {
      "web-01" = { flavor_id = "c6.large.2"; subnet_id = "subnet-pub-1"; system_disk_size = 40 }
      "web-02" = { flavor_id = "c6.large.2"; subnet_id = "subnet-pub-2"; system_disk_size = 40 }
      "app-01" = { flavor_id = "c6.xlarge.2"; subnet_id = "subnet-prv-1"; system_disk_size = 50 }
    }
  }

  assert {
    condition     = length(hcs_ecs_compute_instance.this) == 3
    error_message = "Three ECS instances should be created"
  }

  assert {
    condition     = length(output.instance_ids) == 3
    error_message = "instance_ids output must have three entries"
  }

  assert {
    condition     = length(output.private_ips) == 3
    error_message = "private_ips output must have three entries"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4: EIP is created only when assign_eip = true
# ─────────────────────────────────────────────────────────────────────────────
run "eip_assigned_when_requested" {
  command = apply

  variables {
    name_prefix = "test"
    default_security_group_ids = ["sg-001"]
    instances = {
      "web-01" = {
        flavor_id          = "c6.large.2"
        subnet_id          = "subnet-pub"
        assign_eip         = true
        eip_type           = "eip_public_Internet_01"
        eip_bandwidth_size = 10
      }
      "app-01" = {
        flavor_id  = "c6.large.2"
        subnet_id  = "subnet-prv"
        assign_eip = false
      }
    }
  }

  assert {
    condition     = length(hcs_vpc_eip.this) == 1
    error_message = "Only the web-01 instance should get an EIP"
  }

  assert {
    condition     = length(hcs_ecs_compute_eip_associate.this) == 1
    error_message = "Only one EIP association should be created"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 5: Server groups are created when provided
# ─────────────────────────────────────────────────────────────────────────────
run "server_groups_created" {
  command = apply

  variables {
    name_prefix = "test"
    server_groups = {
      web-aag = { name = "web-anti-affinity"; policies = ["anti-affinity"] }
    }
    instances = {}
  }

  assert {
    condition     = length(hcs_ecs_compute_server_group.this) == 1
    error_message = "One server group should be created"
  }

  assert {
    condition     = hcs_ecs_compute_server_group.this["web-aag"].name == "web-anti-affinity"
    error_message = "Server group name must match"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 6: Keypairs are created when provided
# ─────────────────────────────────────────────────────────────────────────────
run "keypairs_created" {
  command = apply

  variables {
    name_prefix = "test"
    keypairs = {
      bastion-key = { name = "bastion-key" }
    }
    instances = {}
  }

  assert {
    condition     = length(hcs_ecs_compute_keypair.this) == 1
    error_message = "One keypair should be created"
  }

  assert {
    condition     = output.keypair_names["bastion-key"] == "bastion-key"
    error_message = "keypair_names output must contain the created keypair"
  }
}
