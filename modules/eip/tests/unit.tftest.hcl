###############################################################################
# Unit tests: eip module
#
# Uses mock_provider — no HCS credentials required.
# Run:
#   cd modules/eip && terraform test
#   ./scripts/test-module.sh eip --level unit
###############################################################################

mock_provider "hcs" {}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1: No EIPs created when all maps are empty
# ─────────────────────────────────────────────────────────────────────────────
run "empty_configuration" {
  command = apply

  variables {
    name_prefix = "test"
  }

  assert {
    condition     = length(hcs_vpc_eip.dedicated) == 0
    error_message = "No dedicated EIPs should be created with empty config"
  }

  assert {
    condition     = length(hcs_vpc_eip.shared) == 0
    error_message = "No shared EIPs should be created with empty config"
  }

  assert {
    condition     = length(hcs_vpc_bandwidth.this) == 0
    error_message = "No shared bandwidths should be created with empty config"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: Dedicated EIPs are created with their own bandwidth
# ─────────────────────────────────────────────────────────────────────────────
run "dedicated_eips_created" {
  command = apply

  variables {
    name_prefix = "test"
    dedicated_eips = {
      web-01 = { bandwidth_size = 10, ip_type = "eip_public_Internet_01" }
      web-02 = { bandwidth_size = 5, ip_type = "eip_public_Internet_01" }
    }
  }

  assert {
    condition     = length(hcs_vpc_eip.dedicated) == 2
    error_message = "Two dedicated EIPs should be created"
  }

  assert {
    condition     = output.dedicated_eip_ids != {}
    error_message = "dedicated_eip_ids must contain entries"
  }

  assert {
    condition     = length(output.all_eip_addresses) == 2
    error_message = "all_eip_addresses must contain two entries"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: Shared bandwidth is created with correct size
# ─────────────────────────────────────────────────────────────────────────────
run "shared_bandwidth_created" {
  command = apply

  variables {
    name_prefix = "test"
    shared_bandwidths = {
      main-bw = { name = "test-shared-bw", size = 100 }
    }
  }

  assert {
    condition     = length(hcs_vpc_bandwidth.this) == 1
    error_message = "One shared bandwidth should be created"
  }

  assert {
    condition     = hcs_vpc_bandwidth.this["main-bw"].name == "test-shared-bw"
    error_message = "Bandwidth name must match"
  }

  assert {
    condition     = hcs_vpc_bandwidth.this["main-bw"].size == 100
    error_message = "Bandwidth size must be 100"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4: Shared EIPs reference shared bandwidths
# ─────────────────────────────────────────────────────────────────────────────
run "shared_eips_with_bandwidth" {
  command = apply

  variables {
    name_prefix = "test"
    shared_bandwidths = {
      pool = { name = "shared-pool", size = 200 }
    }
    shared_eips = {
      eip-a = { bandwidth_key = "pool" }
      eip-b = { bandwidth_key = "pool" }
    }
  }

  assert {
    condition     = length(hcs_vpc_eip.shared) == 2
    error_message = "Two shared EIPs should be created"
  }

  assert {
    condition     = length(output.shared_eip_ids) == 2
    error_message = "shared_eip_ids must have two entries"
  }
}
