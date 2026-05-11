###############################################################################
# Module: gaussdb – Input Variables
#
# Flexible maps let the calling environment define GaussDB OpenGauss
# instances, parameter templates, and data-source lookups.
###############################################################################

# ─────────────────────────────────────────────
# Instances
# ─────────────────────────────────────────────
variable "instances" {
  description = <<-EOT
    Map of GaussDB OpenGauss instances to create. Key = logical name.

    Required fields:
      name              – Instance name (4-64 chars, starts with letter).
      flavor            – Instance specification string.
      password          – 8-32 chars, ≥3 char types + special (~!@#%^*-_=+?).
      vpc_id            – VPC ID.
      subnet_id         – Subnet (network) ID.
      ha_mode           – "centralization_standard" or "combined".
      volume_type       – "ULTRAHIGH", "LOCALSSD", or "DORADO".
      volume_size       – Volume size in GB.

    Optional fields:
      security_group_id      – Security group ID.
      availability_zone      – Explicit comma-separated AZs (auto-detected if omitted).
      az_count               – Number of AZs to auto-select (default 3).
      solution               – Deployment mode: hcs1–hcs7, triset, quadruset, double, single, logger.
      sharding_num           – 1-9 (distributed mode).
      coordinator_num        – 1-9, ≤ 2×sharding_num.
      replica_num            – 2 or 3 (default 3).
      port                   – Database port (default 8000).
      ha_replication_mode    – "sync" (default).
      ha_consistency         – "strong" or "eventual" (default "strong").
      ha_consistency_protocol – "quorum", "paxos", or "syncStorage".
      datastore_engine       – "GaussDB(for openGauss)".
      datastore_version      – e.g. "8.202".
      backup_start_time      – Backup window start (HH:mm-HH:mm UTC).
      backup_keep_days       – Days to keep backups (default 7).
      kms_tde_key_id         – KMS key ID for transparent data encryption.
      kms_project_name       – KMS project name (required with kms_tde_key_id).
      configuration_key      – Key from var.parameter_templates or "existing:<key>".
      configuration_id       – Explicit parameter template ID (use configuration_key instead when possible).
      enterprise_project_id  – Enterprise project ID.
      time_zone              – Instance time zone.
      timeout_create         – Create timeout (default "120m").
      timeout_update         – Update timeout (default "90m").
      timeout_delete         – Delete timeout (default "45m").
  EOT
  type = map(object({
    name                    = string
    flavor                  = string
    password                = string
    vpc_id                  = string
    subnet_id               = string
    ha_mode                 = string
    volume_type             = string
    volume_size             = number
    security_group_id       = optional(string)
    availability_zone       = optional(string)
    az_count                = optional(number, 3)
    solution                = optional(string)
    sharding_num            = optional(number)
    coordinator_num         = optional(number)
    replica_num             = optional(number)
    port                    = optional(string)
    ha_replication_mode     = optional(string, "sync")
    ha_consistency          = optional(string, "strong")
    ha_consistency_protocol = optional(string)
    datastore_engine        = optional(string)
    datastore_version       = optional(string)
    backup_start_time       = optional(string)
    backup_keep_days        = optional(number, 7)
    kms_tde_key_id          = optional(string)
    kms_project_name        = optional(string)
    configuration_key       = optional(string)
    configuration_id        = optional(string)
    enterprise_project_id   = optional(string)
    time_zone               = optional(string)
    timeout_create          = optional(string, "120m")
    timeout_update          = optional(string, "90m")
    timeout_delete          = optional(string, "45m")
  }))
  default   = {}
  sensitive = false

  validation {
    condition = alltrue([
      for k, v in var.instances :
      can(regex("^[a-zA-Z][a-zA-Z0-9_-]{3,63}$", v.name))
    ])
    error_message = "Instance name must be 4-64 chars, start with a letter, and contain only letters/digits/-/_."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      contains(["centralization_standard", "combined"], v.ha_mode)
    ])
    error_message = "ha_mode must be 'centralization_standard' or 'combined'."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      contains(["ULTRAHIGH", "LOCALSSD", "DORADO"], v.volume_type)
    ])
    error_message = "volume_type must be one of: ULTRAHIGH, LOCALSSD, DORADO."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      v.kms_tde_key_id == null || (v.kms_tde_key_id != null && v.kms_project_name != null)
    ])
    error_message = "kms_project_name is required when kms_tde_key_id is set."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      v.replica_num == null || contains([2, 3], v.replica_num)
    ])
    error_message = "replica_num must be 2 or 3."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      v.sharding_num == null || (v.sharding_num >= 0 && v.sharding_num <= 9)
    ])
    error_message = "sharding_num must be 0-9."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      v.coordinator_num == null || (v.coordinator_num >= 1 && v.coordinator_num <= 9)
    ])
    error_message = "coordinator_num must be 1-9."
  }
}

# ─────────────────────────────────────────────
# Parameter Templates
# ─────────────────────────────────────────────
variable "parameter_templates" {
  description = <<-EOT
    Map of GaussDB OpenGauss parameter templates. Key = logical name.

    For new templates (provide engine_version + instance_mode):
      name            – (Required) Unique, 1-64 chars.
      description     – (Optional) Max 256 chars.
      engine_version  – (Required) e.g. "8.202".
      instance_mode   – (Required) "ha", "combined", "combined_hcs2" … "combined_hcs7".
      parameters      – (Optional) List of { name, value } pairs.

    For copies (provide source_configuration_id only):
      name                    – (Required) Unique, 1-64 chars.
      description             – (Optional) Max 256 chars.
      source_configuration_id – (Required) ID of template to copy.

    Constraint: engine_version/instance_mode and source_configuration_id are mutually exclusive.
  EOT
  type = map(object({
    name                    = string
    description             = optional(string)
    engine_version          = optional(string)
    instance_mode           = optional(string)
    source_configuration_id = optional(string)
    parameters = optional(list(object({
      name  = string
      value = string
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.parameter_templates :
      can(regex("^[a-zA-Z0-9._-]{1,64}$", v.name))
    ])
    error_message = "Template name must be 1-64 chars (letters, digits, -, _, .)."
  }

  validation {
    condition = alltrue([
      for k, v in var.parameter_templates :
      (v.source_configuration_id != null) != (v.engine_version != null || v.instance_mode != null)
    ])
    error_message = "Provide either (engine_version + instance_mode) OR source_configuration_id — not both."
  }
}

# ─────────────────────────────────────────────
# Data Source Lookups — existing resources
# ─────────────────────────────────────────────
variable "existing_instances" {
  description = <<-EOT
    Map of existing GaussDB instances to look up via data source.
    Key = logical reference name. Provide instance name.
  EOT
  type = map(object({
    name = string
  }))
  default = {}
}

variable "existing_parameter_templates" {
  description = <<-EOT
    Map of existing parameter templates to look up via data source.
    Key = logical reference name. Provide template_id.
  EOT
  type = map(object({
    template_id = string
  }))
  default = {}
}
