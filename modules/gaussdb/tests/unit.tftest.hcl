###############################################################################
# Unit tests: gaussdb module
#
# Uses mock_provider — no HCS credentials required.
# Run:
#   cd modules/gaussdb && terraform test
#   ./scripts/test-module.sh gaussdb --level unit
###############################################################################

mock_provider "hcs" {
  mock_data "hcs_availability_zones" {
    defaults = {
      names = ["az1.dc0", "az2.dc0", "az3.dc0"]
    }
  }

  mock_data "hcs_gaussdb_opengauss_instance" {
    defaults = {
      id     = "mock-gaussdb-existing-id"
      status = "normal"
    }
  }

  mock_data "hcs_gaussdb_opengauss_parameter_template" {
    defaults = {
      id = "mock-template-id"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1: Empty instances map creates nothing
# ─────────────────────────────────────────────────────────────────────────────
run "empty_instances" {
  command = apply

  variables {
    instances = {}
  }

  assert {
    condition     = length(hcs_gaussdb_opengauss_instance.this) == 0
    error_message = "No GaussDB instances should be created with empty config"
  }

  assert {
    condition     = output.instance_ids == {}
    error_message = "instance_ids output must be empty"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: GaussDB instance created with required fields
# ─────────────────────────────────────────────────────────────────────────────
run "single_gaussdb_instance" {
  command = apply

  variables {
    instances = {
      primary = {
        name              = "myapp-dev-gaussdb"
        flavor            = "gaussdb.opengauss.ee.dn.m6.2xlarge.8.in"
        password          = "SecureP@ssword1"
        vpc_id            = "vpc-mock-id"
        subnet_id         = "subnet-mock-id"
        ha_mode           = "centralization_standard"
        volume_type       = "ULTRAHIGH"
        volume_size       = 40
      }
    }
  }

  assert {
    condition     = length(hcs_gaussdb_opengauss_instance.this) == 1
    error_message = "One GaussDB instance should be created"
  }

  assert {
    condition     = hcs_gaussdb_opengauss_instance.this["primary"].name == "myapp-dev-gaussdb"
    error_message = "GaussDB instance name must match"
  }

  assert {
    condition     = length(output.instance_ids) == 1
    error_message = "instance_ids must have one entry"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: Parameter template created independently of instances
# ─────────────────────────────────────────────────────────────────────────────
run "parameter_template_created" {
  command = apply

  variables {
    instances = {}
    parameter_templates = {
      perf-template = {
        name           = "high-performance"
        engine_version = "3.1"
        instance_mode  = "enterprise"
        parameters     = [
          { name = "work_mem"; value = "65536" }
        ]
      }
    }
  }

  assert {
    condition     = length(hcs_gaussdb_opengauss_parameter_template.this) == 1
    error_message = "One parameter template should be created"
  }

  assert {
    condition     = hcs_gaussdb_opengauss_parameter_template.this["perf-template"].name == "high-performance"
    error_message = "Template name must match"
  }

  assert {
    condition     = output.template_ids["perf-template"] != ""
    error_message = "template_ids must contain the new template"
  }
}
