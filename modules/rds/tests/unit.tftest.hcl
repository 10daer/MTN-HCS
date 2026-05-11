###############################################################################
# Unit tests: rds module
#
# Uses mock_provider — no HCS credentials required.
# Run:
#   cd modules/rds && terraform test
#   ./scripts/test-module.sh rds --level unit
###############################################################################

mock_provider "hcs" {
  mock_data "hcs_rds_instance" {
    defaults = {
      id          = "mock-existing-rds-id"
      private_ips = ["10.10.10.50"]
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
    condition     = length(hcs_rds_instance.this) == 0
    error_message = "No RDS instances should be created with empty config"
  }

  assert {
    condition     = output.instance_ids == {}
    error_message = "instance_ids output must be empty"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: MySQL instance created with correct engine configuration
# ─────────────────────────────────────────────────────────────────────────────
run "mysql_instance_created" {
  command = apply

  variables {
    instances = {
      primary-db = {
        name              = "myapp-dev-mysql"
        flavor            = "rds.mysql.s1.small"
        vpc_id            = "vpc-mock-id"
        subnet_id         = "subnet-mock-id"
        security_group_id = "sg-mock-id"
        availability_zone = ["az1.dc0"]
        db_type           = "MySQL"
        db_version        = "8.0"
        db_password       = "SecureP@ss123"
        volume_type       = "ULTRAHIGH"
        volume_size       = 100
      }
    }
  }

  assert {
    condition     = length(hcs_rds_instance.this) == 1
    error_message = "One RDS instance should be created"
  }

  assert {
    condition     = hcs_rds_instance.this["primary-db"].name == "myapp-dev-mysql"
    error_message = "RDS instance name must match"
  }

  assert {
    condition     = length(output.instance_ids) == 1
    error_message = "instance_ids output must have one entry"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: MySQL database and account created against an instance
# ─────────────────────────────────────────────────────────────────────────────
run "mysql_database_and_account" {
  command = apply

  variables {
    instances = {
      db = {
        name              = "test-mysql"
        flavor            = "rds.mysql.s1.small"
        vpc_id            = "vpc-id"
        subnet_id         = "subnet-id"
        security_group_id = "sg-id"
        availability_zone = ["az1.dc0"]
        db_type           = "MySQL"
        db_version        = "8.0"
        db_password       = "P@ssword123"
        volume_type       = "ULTRAHIGH"
        volume_size       = 50
      }
    }
    mysql_databases = {
      app-db = { instance_key = "db", name = "appdb", character_set = "utf8mb4" }
    }
    mysql_accounts = {
      app-user = { instance_key = "db", name = "appuser", password = "UserP@ss123" }
    }
  }

  assert {
    condition     = length(hcs_rds_mysql_database.this) == 1
    error_message = "One MySQL database should be created"
  }

  assert {
    condition     = hcs_rds_mysql_database.this["app-db"].name == "appdb"
    error_message = "Database name must match"
  }

  assert {
    condition     = length(hcs_rds_mysql_account.this) == 1
    error_message = "One MySQL account should be created"
  }

  assert {
    condition     = output.mysql_database_names["app-db"] == "appdb"
    error_message = "mysql_database_names output must contain the created database"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4: Multiple RDS instances (multi-tier)
# ─────────────────────────────────────────────────────────────────────────────
run "multiple_instances" {
  command = apply

  variables {
    instances = {
      mysql-01 = {
        name              = "db-mysql", flavor = "rds.mysql.s1.small"
        vpc_id            = "vpc-id", subnet_id = "subnet-id", security_group_id = "sg-id"
        availability_zone = ["az1.dc0"]
        db_type           = "MySQL", db_version = "8.0", db_password = "Pass123!"
        volume_type       = "ULTRAHIGH", volume_size = 100
      }
      pg-01 = {
        name              = "db-pg", flavor = "rds.pg.s1.small"
        vpc_id            = "vpc-id", subnet_id = "subnet-id", security_group_id = "sg-id"
        availability_zone = ["az1.dc0"]
        db_type           = "PostgreSQL", db_version = "14", db_password = "Pass123!"
        volume_type       = "ULTRAHIGH", volume_size = 100
      }
    }
  }

  assert {
    condition     = length(hcs_rds_instance.this) == 2
    error_message = "Two RDS instances should be created"
  }
}
