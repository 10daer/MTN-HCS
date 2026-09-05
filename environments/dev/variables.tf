# ─────────────────────────────────────────────
# HCS Provider / Connection
# ─────────────────────────────────────────────
variable "access_key" {
  description = "HCS Access Key (AK). Set via TF_VAR_access_key env var — do not hardcode."
  type        = string
  sensitive   = true
}

variable "secret_key" {
  description = "HCS Secret Key (SK). Set via TF_VAR_secret_key env var — do not hardcode."
  type        = string
  sensitive   = true
}

variable "hcs_auth_url" {
  description = <<-EOT
    REQUIRED for HCS private cloud. The IAM endpoint URL — used by the
    provider to authenticate and to resolve project_name to a project ID.

    Format:  https://iam-apigateway-proxy.<your-hcs-domain>/v3
    Example: https://iam-apigateway-proxy.mtn.com/v3

    If left empty, the provider builds a malformed URL like
    https://iam-apigateway-proxy.:443/... and every API call fails.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.hcs_auth_url == "" || can(regex("^https?://[^/]+/v3/?$", var.hcs_auth_url))
    error_message = "hcs_auth_url should end in /v3 — example: https://iam-apigateway-proxy.your-domain/v3"
  }
}

variable "region" {
  description = "HCS region name"
  type        = string
}

variable "domain_name" {
  description = "HCS account domain name (tenant)"
  type        = string
}

variable "project_name" {
  description = "HCS project name / VDC (maps to a region project)"
  type        = string
}

variable "skip_tls_verify" {
  description = "Skip TLS verification for self-signed certs on private HCS"
  type        = bool
  default     = false
}

variable "endpoints" {
  description = <<-EOT
    Map of custom HCS service endpoint overrides.
    Keys match HCS provider endpoint names: ecs, ims, vpc, evs, nat, obs, iam, etc.
    Leave empty {} to use provider defaults.
  EOT
  type        = map(string)
  default     = {}
}

# ─────────────────────────────────────────────
# Resource Naming & Tagging
# ─────────────────────────────────────────────
variable "project" {
  description = "Project name — used in resource names and tags"
  type        = string
}

variable "environment" {
  description = "Environment name: dev, staging, prod"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Team or person owning these resources"
  type        = string
}

# ─────────────────────────────────────────────
# Network
# ─────────────────────────────────────────────
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

# VPC names must be unique inside an HCS project. Leave null to use
# "<project>-<environment>-vpc"; set it when that name is already taken by a
# VPC that is not managed by this state.
variable "vpc_name" {
  type    = string
  default = null
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.10.0/24", "10.10.11.0/24"]
}

variable "availability_zones" {
  description = "Optional AZ override. Left empty by default — AZs are discovered from the live stack (data.hcs_availability_zones) instead of being hardcoded."
  type        = list(string)
  default     = []
}

variable "dns_servers" {
  type    = list(string)
  default = ["100.125.4.25"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

variable "eip_type" {
  description = "EIP publicip type — depends on HCS environment (e.g. eip_public_Internet_01)."
  type        = string
  default     = "eip_public_Internet_01"
}

variable "security_groups" {
  description = <<-EOT
    Security groups to create, consumed by main-security.tf. Set in
    security.auto.tfvars, which ships with this environment's "server" group.
    Key = group suffix; value = { description, ingress_rules = [...] }.
    See modules/security/variables.tf for the rule schema.
  EOT
  type        = any
  default     = {}
}

variable "trusted_ssh_cidr" {
  description = "CIDR allowed to SSH to bastion. Restrict tightly."
  type        = string
}

# ─────────────────────────────────────────────
# EIP — Elastic IPs & Bandwidth
# ─────────────────────────────────────────────
variable "eip_shared_bandwidths" {
  description = "Map of shared bandwidths. See modules/eip/variables.tf for full schema."
  type = map(object({
    name                  = string
    size                  = number
    enterprise_project_id = optional(string)
  }))
  default = {}
}

variable "eip_dedicated" {
  description = "Map of dedicated-bandwidth EIPs. See modules/eip/variables.tf."
  type = map(object({
    bandwidth_size        = number
    bandwidth_name        = optional(string)
    ip_type               = optional(string, "eip")
    ip_address            = optional(string)
    name                  = optional(string)
    enterprise_project_id = optional(string)
  }))
  default = {}
}

variable "eip_shared" {
  description = "Map of shared-bandwidth EIPs. See modules/eip/variables.tf."
  type = map(object({
    bandwidth_key         = string
    ip_type               = optional(string, "eip")
    ip_address            = optional(string)
    name                  = optional(string)
    enterprise_project_id = optional(string)
  }))
  default = {}
}

variable "eip_bandwidth_associations" {
  description = "Map of bandwidth association bindings. See modules/eip/variables.tf."
  type = map(object({
    bandwidth_key           = string
    eip_key                 = string
    fallback_bandwidth_size = optional(number, 5)
  }))
  default = {}
}

variable "eip_associations" {
  description = "Map of EIP-to-port/IP bindings. See modules/eip/variables.tf."
  type = map(object({
    eip_key    = string
    port_id    = optional(string)
    fixed_ip   = optional(string)
    network_id = optional(string)
  }))
  default = {}
}

variable "eip_external_bandwidth_ids" {
  description = "Map of external bandwidth IDs for cross-module references."
  type        = map(string)
  default     = {}
}

variable "eip_external_eip_ids" {
  description = "Map of external EIP IDs for cross-module references."
  type        = map(string)
  default     = {}
}

variable "eip_external_eip_addresses" {
  description = "Map of external EIP addresses for cross-module references."
  type        = map(string)
  default     = {}
}

# ─────────────────────────────────────────────
# ECS — Instances (Web & App Tiers)
# ─────────────────────────────────────────────
variable "key_pair_name" {
  description = "Default SSH key pair injected into all ECS instances. Unused by the web tier (which mirrors the standalone config and sets no keypair); kept for other tiers."
  type        = string
  default     = ""
}

variable "image_name" {
  description = "Default image name filter for ECS instances."
  type        = string
  default     = "Ubuntu 22.04 server 64bit"
}

variable "server_ssh_public_key" {
  description = "Contents of an SSH public key (e.g. ~/.ssh/id_rsa.pub) imported as the web keypair. Leave empty to create the instance with no keypair (matches the standalone config)."
  type        = string
  default     = ""
}

# ── Web Tier ─────────────────────────────────
variable "web_instance_count" {
  description = "Number of web tier ECS instances to create."
  type        = number
  default     = 2
}

# Flavor is discovered by vCPU/RAM (see data.hcs_ecs_compute_flavors.web in
# main.tf) rather than hardcoded — a fixed flavor ID like "c6.large.2" is a
# public-cloud name that does not exist on the MTN Lagos private stack.
variable "web_flavor_cpu" {
  description = "vCPU count used to discover the web tier flavor."
  type        = number
  default     = 2
}

variable "web_flavor_memory" {
  description = "Memory (GB) used to discover the web tier flavor."
  type        = number
  default     = 4
}

variable "web_eip_bandwidth_size" {
  description = "Bandwidth (Mbit/s) for the web tier EIP created by the ecs module."
  type        = number
  default     = 10
}

variable "web_system_disk_type" {
  description = "System disk type for web tier instances (e.g. SATA, SAS, SSD)."
  type        = string
  default     = "SATA"
}

variable "web_system_disk_size" {
  description = "System disk size in GB for web tier instances."
  type        = number
  default     = 50
}

variable "ecs_web_server_groups" {
  description = "Server groups (anti-affinity/affinity) for the web tier. See modules/ecs/variables.tf."
  type = map(object({
    name     = string
    policies = list(string)
  }))
  default = {
    web_anti_affinity = {
      name     = "web-anti-affinity"
      policies = ["anti-affinity"]
    }
  }
}

variable "ecs_web_subnet_id" {
  description = "Explicit subnet ID for web tier instances. Empty = use the network stack's first public subnet."
  type        = string
  default     = ""
}

variable "ecs_web_security_group_ids" {
  description = "Explicit security group IDs for web tier instances. Empty = use module.security's \"server\" group plus the network default SG."
  type        = list(string)
  default     = []
}

variable "ecs_web_keypairs" {
  description = "Managed keypairs for the web tier. See modules/ecs/variables.tf."
  type = map(object({
    name       = string
    key_file   = optional(string)
    public_key = optional(string)
  }))
  default = {}
}

# ── App Tier ─────────────────────────────────
variable "app_instance_count" {
  description = "Number of app tier ECS instances to create."
  type        = number
  default     = 2
}

variable "app_flavor_id" {
  description = "Flavor for app tier instances e.g. c6.xlarge.2."
  type        = string
  default     = "c6.xlarge.2"
}

variable "app_system_disk_type" {
  description = "System disk type for app tier instances."
  type        = string
  default     = "business_type_01"
}

variable "app_system_disk_size" {
  description = "System disk size in GB for app tier instances."
  type        = number
  default     = 50
}

variable "app_data_disk_size" {
  description = "Data disk size in GB attached to each app tier instance."
  type        = number
  default     = 100
}

variable "ecs_app_server_groups" {
  description = "Server groups (anti-affinity/affinity) for the app tier. See modules/ecs/variables.tf."
  type = map(object({
    name     = string
    policies = list(string)
  }))
  default = {
    app_anti_affinity = {
      name     = "app-anti-affinity"
      policies = ["anti-affinity"]
    }
  }
}

variable "ecs_app_keypairs" {
  description = "Managed keypairs for the app tier. See modules/ecs/variables.tf."
  type = map(object({
    name       = string
    key_file   = optional(string)
    public_key = optional(string)
  }))
  default = {}
}

# ─────────────────────────────────────────────
# CCE — Kubernetes Cluster
# ─────────────────────────────────────────────
variable "cce_enabled" {
  description = "Create the CCE cluster. A cluster is not map-driven, so this flag is what keeps the stack off."
  type        = bool
  default     = false
}

variable "cce_vpc_id" {
  description = "Explicit VPC ID for the CCE cluster. Empty = use the network stack's VPC."
  type        = string
  default     = ""
}

variable "cce_subnet_id" {
  description = "Explicit subnet ID for the CCE cluster (must have DNS configured). Empty = network stack's first public subnet."
  type        = string
  default     = ""
}

variable "cce_key_pair_name" {
  description = "SSH key pair for CCE nodes (must already exist in HCS). Empty = fall back to var.key_pair_name."
  type        = string
  default     = ""
}

variable "cce_cluster_name" {
  description = <<-EOT
    Explicit CCE cluster name. Empty = derive it from name_prefix, lowercased
    with illegal characters replaced by hyphens (CCE allows only lowercase
    letters, digits and hyphens). Set this only to override that.
  EOT
  type        = string
  default     = ""
}

variable "cce_cluster_flavor_id" {
  description = "CCE cluster size. cce.s1.small (single, 50 nodes) / cce.s2.small (HA, 50 nodes) etc."
  type        = string
  default     = "cce.s1.small"
}

variable "cce_container_network_type" {
  description = "Container networking: overlay_l2, vpc-router, or eni"
  type        = string
  default     = "overlay_l2"
}

variable "cce_container_network_cidr" {
  description = "Container network CIDR (leave empty for default)"
  type        = string
  default     = ""
}

variable "cce_service_network_cidr" {
  description = "Service network CIDR (leave empty for default)"
  type        = string
  default     = ""
}

variable "cce_kube_proxy_mode" {
  description = "Service forwarding: iptables or ipvs"
  type        = string
  default     = "iptables"
}

variable "cce_cluster_eip" {
  description = "EIP address for the K8s API server (leave empty for private-only)"
  type        = string
  default     = ""
}

variable "cce_cluster_multi_az" {
  description = "Spread master nodes across AZs (only for HA cce.s2.* flavors)"
  type        = bool
  default     = false
}

variable "cce_node_pools" {
  description = "Map of CCE node pools. See modules/cce/variables.tf for full schema."
  type        = any
  default     = {}
}

variable "cce_namespaces" {
  description = "Map of K8s namespaces to create. Key = namespace name."
  type = map(object({
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})
  }))
  default = {}
}

# ─────────────────────────────────────────────
# VDC — Users, Groups, Roles, Projects
# ─────────────────────────────────────────────
variable "vdc_id" {
  description = "VDC ID (1-36 chars, lowercase letters/digits/hyphens). Unused unless module.vdc is re-added to main.tf."
  type        = string
  default     = ""
}

variable "domain_id" {
  description = "Tenant (domain) ID for tenant-level role assignments."
  type        = string
  default     = ""
}

variable "vdc_users" {
  description = "Map of VDC users to create. See modules/vdc/variables.tf for full schema."
  type = map(object({
    name         = string
    password     = optional(string)
    display_name = optional(string)
    auth_type    = optional(string, "LOCAL_AUTH")
    enabled      = optional(bool, true)
    description  = optional(string)
    access_mode  = optional(string, "default")
  }))
  default = {}
}

variable "vdc_groups" {
  description = "Map of VDC groups to create. See modules/vdc/variables.tf for full schema."
  type = map(object({
    name        = string
    description = optional(string)
  }))
  default = {}
}

variable "vdc_roles" {
  description = "Map of custom VDC roles to create. See modules/vdc/variables.tf for full schema."
  type = map(object({
    name        = string
    description = optional(string)
    type        = optional(string, "XA")
    policy      = string
  }))
  default = {}
}

variable "vdc_projects" {
  description = "Map of VDC projects (resource spaces) to create."
  type = map(object({
    name         = string
    display_name = optional(string)
    description  = optional(string)
  }))
  default = {}
}

variable "vdc_group_memberships" {
  description = "Map of group → user memberships. See modules/vdc/variables.tf for full schema."
  type = map(object({
    group_key = string
    user_keys = list(string)
  }))
  default = {}
}

variable "vdc_group_role_assignments" {
  description = "Map of group role assignments. See modules/vdc/variables.tf for full schema."
  type = map(object({
    group_key = string
    assignments = list(object({
      role_key              = string
      domain_id             = optional(string)
      project_key           = optional(string)
      project_id            = optional(string)
      enterprise_project_id = optional(string)
    }))
  }))
  default = {}
}

variable "vdc_existing_roles" {
  description = "Map of existing VDC roles to look up."
  type = map(object({
    display_name = optional(string)
    name         = optional(string)
  }))
  default = {}
}

variable "vdc_existing_groups" {
  description = "Map of existing VDC groups to look up."
  type = map(object({
    name = string
  }))
  default = {}
}

variable "vdc_existing_users" {
  description = "Map of existing VDC users to look up."
  type = map(object({
    name = string
  }))
  default = {}
}

# ─────────────────────────────────────────────
# OBS — Object Storage Service
# ─────────────────────────────────────────────
variable "obs_buckets" {
  description = "Map of OBS buckets. See modules/obs/variables.tf for full schema."
  type        = any
  default     = {}
}

variable "obs_bucket_acls" {
  description = "Map of fine-grained bucket ACLs. See modules/obs/variables.tf."
  type        = any
  default     = {}
}

variable "obs_objects" {
  description = "Map of objects to upload to OBS buckets. See modules/obs/variables.tf."
  type        = any
  default     = {}
}

variable "obs_object_acls" {
  description = "Map of fine-grained object ACLs. See modules/obs/variables.tf."
  type        = any
  default     = {}
}

variable "obs_bucket_policies" {
  description = "Map of bucket policies to apply. See modules/obs/variables.tf."
  type        = any
  default     = {}
}

variable "obs_existing_buckets" {
  description = "Map of existing OBS buckets to look up. See modules/obs/variables.tf."
  type = map(object({
    bucket = string
  }))
  default = {}
}

# ─────────────────────────────────────────────
# GaussDB OpenGauss
# ─────────────────────────────────────────────
variable "gaussdb_instances" {
  description = "Map of GaussDB OpenGauss instances. See modules/gaussdb/variables.tf for full schema."
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
  default = {}
}

variable "gaussdb_parameter_templates" {
  description = "Map of GaussDB parameter templates. See modules/gaussdb/variables.tf for full schema."
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
}

variable "gaussdb_existing_instances" {
  description = "Map of existing GaussDB instances to look up."
  type = map(object({
    name = string
  }))
  default = {}
}

variable "gaussdb_existing_parameter_templates" {
  description = "Map of existing GaussDB parameter templates to look up."
  type = map(object({
    template_id = string
  }))
  default = {}
}

# ─────────────────────────────────────────────
# RDS — Relational Database Service
# ─────────────────────────────────────────────
variable "rds_instances" {
  description = "Map of RDS instances. See modules/rds/variables.tf for full schema."
  type        = any
  default     = {}
}

variable "rds_mysql_databases" {
  description = "Map of MySQL databases. See modules/rds/variables.tf."
  type = map(object({
    instance_key  = string
    name          = string
    character_set = optional(string, "utf8mb4")
    description   = optional(string)
  }))
  default = {}
}

variable "rds_mysql_accounts" {
  description = "Map of MySQL accounts. See modules/rds/variables.tf."
  type = map(object({
    instance_key = string
    name         = string
    password     = string
    hosts        = optional(list(string), ["%"])
  }))
  default = {}
  # NOTE: do not mark sensitive — Terraform forbids sensitive values as for_each
  # keys. Password is already redacted by the provider in plan/apply output.
}

variable "rds_mysql_privileges" {
  description = "Map of MySQL database privilege grants. See modules/rds/variables.tf."
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

variable "rds_pg_databases" {
  description = "Map of PostgreSQL databases. See modules/rds/variables.tf."
  type = map(object({
    instance_key = string
    name         = string
    owner        = optional(string, "rdsAdmin")
  }))
  default = {}
}

variable "rds_pg_accounts" {
  description = "Map of PostgreSQL accounts. See modules/rds/variables.tf."
  type = map(object({
    instance_key = string
    name         = string
    password     = string
  }))
  default = {}
  # NOTE: do not mark sensitive — Terraform forbids sensitive values as for_each
  # keys. Password is already redacted by the provider in plan/apply output.
}

variable "rds_pg_privileges" {
  description = "Map of PostgreSQL privilege grants. See modules/rds/variables.tf."
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

variable "rds_pg_plugins" {
  description = "Map of PostgreSQL plugins to enable. See modules/rds/variables.tf."
  type = map(object({
    instance_key = string
    db_key       = string
    name         = string
  }))
  default = {}
}

variable "rds_sql_audits" {
  description = "Map of SQL audit configs. See modules/rds/variables.tf."
  type = map(object({
    instance_key = string
    keep_days    = number
    audit_types  = list(string)
  }))
  default = {}
}

variable "rds_existing_instances" {
  description = "Map of existing RDS instances to look up."
  type = map(object({
    name = string
  }))
  default = {}
}
