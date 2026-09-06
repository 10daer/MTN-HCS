###############################################################################
# Module: rds – Input Variables
#
# Manages RDS instances (MySQL / PostgreSQL), databases, accounts, privileges,
# plugins, and SQL audit on Huawei Cloud Stack (HCS).
###############################################################################

# ─────────────────────────────────────────────
# RDS Instances
# ─────────────────────────────────────────────
variable "instance_ready_delay" {
  description = <<-EOT
    How long to wait after an RDS instance is created before issuing database
    or account jobs against it. The API reports the instance complete before it
    accepts management jobs, and the first job then fails with HTTP 500
    "RDS.0005 Server error". Raise this if that still occurs.
  EOT
  type        = string
  default     = "90s"
}

variable "instances" {
  description = <<-EOT
    Map of RDS instances to create.
    Key = logical instance identifier.

    Fields:
      name                – (Required) Instance name (4-64 chars).
      flavor              – (Required) Flavor ID. Use ".ha" suffix for HA.
      vpc_id              – (Required, ForceNew) VPC ID.
      subnet_id           – (Required, ForceNew) Subnet ID.
      security_group_id   – (Required) Security group ID.
      availability_zone   – (Required, ForceNew) list(string) — 1 AZ (single) or 2 AZs (HA).

      db_type             – (Required, ForceNew) "MySQL" or "PostgreSQL".
      db_version          – (Required, ForceNew) Engine version string.
      db_password         – (Required) Database root password.
      db_port             – (Optional) Custom port.

      volume_type         – (Required) "ULTRAHIGH" | "LOCALSSD" | "CLOUDSSD" | "ESSD".
      volume_size         – (Required) Volume size in GB.

      ha_replication_mode – (Optional) "async" | "semisync" (MySQL) or "async" | "sync" (PostgreSQL).
      backup_start_time   – (Optional) Backup window e.g. "08:00-09:00".
      backup_keep_days    – (Optional) Backup retention days. Default: 7.
      backup_period       – (Optional) Backup period (comma-separated days).

      parameters          – (Optional) list(object({ name, value })) — DB parameters.
      lower_case_table_names – (Optional) String — MySQL only.
      time_zone           – (Optional) String.
      ssl_enable          – (Optional) Bool.
      description         – (Optional) String.
      enterprise_project_id – (Optional) String.
      param_group_id      – (Optional) Pre-existing parameter group ID.
      tags                – (Optional) map(string).

      timeout_create      – (Optional) Timeout. Default: "30m".
      timeout_update      – (Optional) Timeout. Default: "30m".
      timeout_delete      – (Optional) Timeout. Default: "30m".
  EOT
  type        = any
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.instances :
      contains(["MySQL", "PostgreSQL"], v.db_type)
    ])
    error_message = "Each instance.db_type must be 'MySQL' or 'PostgreSQL'."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      contains(["ULTRAHIGH", "LOCALSSD", "CLOUDSSD", "ESSD"], v.volume_type)
    ])
    error_message = "Each instance.volume_type must be one of: ULTRAHIGH, LOCALSSD, CLOUDSSD, ESSD."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      length(v.name) >= 4 && length(v.name) <= 64
    ])
    error_message = "Each instance.name must be 4-64 characters."
  }
}

# ─────────────────────────────────────────────
# MySQL Databases
# ─────────────────────────────────────────────
variable "mysql_databases" {
  description = <<-EOT
    Map of MySQL databases to create.
    Key = logical name.

    Fields:
      instance_key  – (Required) Key referencing a MySQL instance in var.instances.
      name          – (Required) Database name.
      character_set – (Optional) Default: "utf8mb4".
      description   – (Optional) Description.
  EOT
  type = map(object({
    instance_key  = string
    name          = string
    character_set = optional(string, "utf8mb4")
    description   = optional(string)
  }))
  default = {}
}

# ─────────────────────────────────────────────
# MySQL Accounts
# ─────────────────────────────────────────────
variable "mysql_accounts" {
  description = <<-EOT
    Map of MySQL accounts to create.
    Key = logical name.

    Fields:
      instance_key – (Required) Key referencing a MySQL instance in var.instances.
      name         – (Required) Account name.
      password     – (Required) Account password.
      hosts        – (Optional) list(string) — allowed hosts. Default: ["%"].
  EOT
  type = map(object({
    instance_key = string
    name         = string
    password     = string
    hosts        = optional(list(string), ["%"])
  }))
  default = {}
  # NOTE: do not mark this whole map sensitive — Terraform forbids sensitive
  # values as for_each keys. The password field is already redacted by the
  # provider schema on hcs_rds_mysql_account.password, so plan/apply output
  # will not leak the password.
}

# ─────────────────────────────────────────────
# MySQL Database Privileges
# ─────────────────────────────────────────────
variable "mysql_privileges" {
  description = <<-EOT
    Map of MySQL database privilege grants.
    Key = logical name.

    Fields:
      instance_key – (Required) Key referencing a MySQL instance in var.instances.
      db_key       – (Required) Key referencing a database in var.mysql_databases.
      users        – (Required) list(object({ account_key, readonly }))
                     account_key references a key in var.mysql_accounts.
                     readonly = bool — true for read-only, false for read-write.
  EOT
  type = map(object({
    instance_key = string
    db_key       = string
    users = list(object({
      account_key = string
      readonly    = optional(bool, false)
    }))
  }))
  default = {}
}

# ─────────────────────────────────────────────
# PostgreSQL Databases
# ─────────────────────────────────────────────
variable "pg_databases" {
  description = <<-EOT
    Map of PostgreSQL databases to create.
    Key = logical name.

    Fields:
      instance_key – (Required) Key referencing a PostgreSQL instance in var.instances.
      name         – (Required) Database name.
      owner        – (Optional) Database owner. Default: "rdsAdmin".
  EOT
  type = map(object({
    instance_key = string
    name         = string
    owner        = optional(string, "rdsAdmin")
  }))
  default = {}
}

# ─────────────────────────────────────────────
# PostgreSQL Accounts
# ─────────────────────────────────────────────
variable "pg_accounts" {
  description = <<-EOT
    Map of PostgreSQL accounts to create.
    Key = logical name.

    Fields:
      instance_key – (Required) Key referencing a PostgreSQL instance in var.instances.
      name         – (Required) Account name.
      password     – (Required) Account password.
  EOT
  type = map(object({
    instance_key = string
    name         = string
    password     = string
  }))
  default = {}
  # NOTE: see mysql_accounts above — Terraform forbids sensitive values as
  # for_each keys; password is already sensitive at the resource level.
}

# ─────────────────────────────────────────────
# PostgreSQL Database Privileges
# ─────────────────────────────────────────────
variable "pg_privileges" {
  description = <<-EOT
    Map of PostgreSQL database privilege grants.
    Key = logical name.

    Fields:
      instance_key – (Required) Key referencing a PostgreSQL instance in var.instances.
      db_key       – (Required) Key referencing a database in var.pg_databases.
      users        – (Required) list(object({ account_key, schema_name, readonly }))
                     account_key references a key in var.pg_accounts.
                     schema_name = PostgreSQL schema (default "public").
                     readonly = bool.
  EOT
  type = map(object({
    instance_key = string
    db_key       = string
    users = list(object({
      account_key = string
      schema_name = optional(string, "public")
      readonly    = optional(bool, false)
    }))
  }))
  default = {}
}

# ─────────────────────────────────────────────
# PostgreSQL Plugins
# ─────────────────────────────────────────────
variable "pg_plugins" {
  description = <<-EOT
    Map of PostgreSQL plugins to enable.
    Key = logical name.

    Fields:
      instance_key – (Required) Key referencing a PostgreSQL instance in var.instances.
      db_key       – (Required) Key referencing a database in var.pg_databases.
      name         – (Required) Plugin name (e.g. "pgaudit", "pg_stat_statements").
  EOT
  type = map(object({
    instance_key = string
    db_key       = string
    name         = string
  }))
  default = {}
}

# ─────────────────────────────────────────────
# SQL Audit
# ─────────────────────────────────────────────
variable "sql_audits" {
  description = <<-EOT
    Map of SQL audit configurations.
    Key = logical name.

    Fields:
      instance_key – (Required) Key referencing an instance in var.instances.
      keep_days    – (Required) Audit log retention in days.
      audit_types  – (Required) list(string) — e.g. ["INSERT", "DELETE", "UPDATE", "CREATE_USER", "DROP_USER"].
  EOT
  type = map(object({
    instance_key = string
    keep_days    = number
    audit_types  = list(string)
  }))
  default = {}
}

# ─────────────────────────────────────────────
# Data-source lookups
# ─────────────────────────────────────────────
variable "existing_instances" {
  description = <<-EOT
    NOT CURRENTLY SUPPORTED — kept for backward compatibility only.

    The huaweicloud/hcs ~> 2.4.0 provider does not expose an
    `hcs_rds_instance` data source, so this module cannot look up
    pre-existing RDS instances by name. Must be left as {}.

    If you need to reference an unmanaged instance, pass the instance
    ID directly as a string in your downstream resource references.
  EOT
  type = map(object({
    name = string
  }))
  default = {}

  validation {
    condition     = length(var.existing_instances) == 0
    error_message = "existing_instances is not supported (no hcs_rds_instance data source in the provider). Pass instance IDs directly as strings instead."
  }
}
