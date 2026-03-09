###############################################################################
# Unit tests: cce module
#
# Uses mock_provider — no HCS credentials required.
# Run:
#   cd modules/cce && terraform test
#   ./scripts/test-module.sh cce --level unit
###############################################################################

mock_provider "hcs" {
  mock_data "hcs_cce_nodes" {
    defaults = {
      ids   = ["mock-node-id-1", "mock-node-id-2"]
      nodes = []
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1: CCE cluster is created with correct naming
# ─────────────────────────────────────────────────────────────────────────────
run "cluster_created_with_correct_name" {
  command = apply

  variables {
    name_prefix            = "myapp-dev"
    cluster_flavor_id      = "cce.s1.small"
    vpc_id                 = "vpc-mock-id"
    subnet_id              = "subnet-mock-id"
    key_pair_name          = "my-keypair"
    container_network_type = "overlay_l2"
    node_pools             = {}
    namespaces             = {}
  }

  assert {
    condition     = hcs_cce_cluster.this.name == "myapp-dev-cluster"
    error_message = "CCE cluster name must be '<name_prefix>-cluster'"
  }

  assert {
    condition     = hcs_cce_cluster.this.flavor_id == "cce.s1.small"
    error_message = "CCE cluster flavor must match"
  }

  assert {
    condition     = output.cluster_id != ""
    error_message = "cluster_id output must not be empty"
  }

  assert {
    condition     = output.cluster_name == "myapp-dev-cluster"
    error_message = "cluster_name output must match"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: Node pools are created with correct naming
# ─────────────────────────────────────────────────────────────────────────────
run "node_pools_created" {
  command = apply

  variables {
    name_prefix            = "myapp-dev"
    cluster_flavor_id      = "cce.s1.small"
    vpc_id                 = "vpc-id"
    subnet_id              = "subnet-id"
    key_pair_name          = "kp"
    container_network_type = "overlay_l2"
    node_pools = {
      workers = {
        flavor_id          = "s3.large.4"
        initial_node_count = 2
        availability_zone  = "az1.dc0"
      }
    }
    namespaces = {}
  }

  assert {
    condition     = length(hcs_cce_node_pool.pools) == 1
    error_message = "One node pool should be created"
  }

  assert {
    condition     = hcs_cce_node_pool.pools["workers"].name == "myapp-dev-workers"
    error_message = "Node pool name must be '<name_prefix>-<pool_key>'"
  }

  assert {
    condition     = hcs_cce_node_pool.pools["workers"].initial_node_count == 2
    error_message = "Node pool initial count must match"
  }

  assert {
    condition     = length(output.node_pool_ids) == 1
    error_message = "node_pool_ids must contain one entry"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: Multiple node pools (workers + spot pool)
# ─────────────────────────────────────────────────────────────────────────────
run "multiple_node_pools" {
  command = apply

  variables {
    name_prefix            = "test"
    cluster_flavor_id      = "cce.s1.small"
    vpc_id                 = "vpc-id"
    subnet_id              = "subnet-id"
    key_pair_name          = "kp"
    container_network_type = "overlay_l2"
    node_pools = {
      workers = { flavor_id = "s3.large.4"; initial_node_count = 3; availability_zone = "az1.dc0" }
      gpu     = { flavor_id = "p3.large.4"; initial_node_count = 1; availability_zone = "az1.dc0" }
    }
    namespaces = {}
  }

  assert {
    condition     = length(hcs_cce_node_pool.pools) == 2
    error_message = "Two node pools should be created"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4: Kubernetes namespaces are created
# ─────────────────────────────────────────────────────────────────────────────
run "namespaces_created" {
  command = apply

  variables {
    name_prefix            = "test"
    cluster_flavor_id      = "cce.s1.small"
    vpc_id                 = "vpc-id"
    subnet_id              = "subnet-id"
    key_pair_name          = "kp"
    container_network_type = "overlay_l2"
    node_pools             = {}
    namespaces = {
      app        = { labels = { team = "backend" } }
      monitoring = { labels = { team = "platform" } }
      staging    = {}
    }
  }

  assert {
    condition     = length(hcs_cce_namespace.namespaces) == 3
    error_message = "Three Kubernetes namespaces should be created"
  }

  assert {
    condition     = length(output.namespace_names) == 3
    error_message = "namespace_names output must have three entries"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 5: Cluster with no pools or namespaces (minimal)
# ─────────────────────────────────────────────────────────────────────────────
run "minimal_cluster" {
  command = apply

  variables {
    name_prefix            = "minimal"
    cluster_flavor_id      = "cce.s1.small"
    vpc_id                 = "vpc-id"
    subnet_id              = "subnet-id"
    key_pair_name          = "kp"
    container_network_type = "overlay_l2"
    node_pools             = {}
    namespaces             = {}
  }

  assert {
    condition     = length(hcs_cce_node_pool.pools) == 0
    error_message = "No node pools when node_pools is empty"
  }

  assert {
    condition     = length(hcs_cce_namespace.namespaces) == 0
    error_message = "No namespaces when namespaces is empty"
  }
}
