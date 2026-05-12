###############################################################################
# Dev Environment — root module
# Orchestrates: vdc → network → security → eip → ecs → obs → cce → gaussdb → rds
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
    Region      = var.region
  }
}

# ─────────────────────────────────────────────
# 0. VDC — Users, Groups, Roles, Projects, Assignments
# ─────────────────────────────────────────────
module "vdc" {
  source = "../../modules/vdc"

  vdc_id    = var.vdc_id
  domain_id = var.domain_id
  region_id = var.region

  # Custom roles
  roles = var.vdc_roles

  # Projects (resource spaces)
  projects = var.vdc_projects

  # Users
  users = var.vdc_users

  # Groups
  groups = var.vdc_groups

  # Group memberships
  group_memberships = var.vdc_group_memberships

  # Group role assignments
  group_role_assignments = var.vdc_group_role_assignments

  # Data-source lookups for existing resources
  existing_roles  = var.vdc_existing_roles
  existing_groups = var.vdc_existing_groups
  existing_users  = var.vdc_existing_users
}

# ─────────────────────────────────────────────
# 1. Network
# ─────────────────────────────────────────────
module "network" {
  source = "../../modules/network"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  dns_servers          = var.dns_servers
  enable_nat_gateway   = var.enable_nat_gateway
  nat_gateway_spec     = "1" # small — sufficient for dev
  nat_bandwidth_size   = 10
  eip_type             = var.eip_type
}

# ─────────────────────────────────────────────
# 2. Security Groups
# ─────────────────────────────────────────────
module "security" {
  source = "../../modules/security"

  name_prefix = local.name_prefix

  security_groups = {
    bastion = {
      description = "Bastion host — SSH ingress from trusted CIDRs only"
      ingress_rules = [
        {
          protocol    = "tcp"
          port_min    = 22
          port_max    = 22
          cidr        = var.trusted_ssh_cidr
          description = "SSH from trusted network"
        }
      ]
    }
    web = {
      description = "Web tier — HTTP/HTTPS from internet"
      ingress_rules = [
        { protocol = "tcp", port_min = 80, port_max = 80, cidr = "0.0.0.0/0", description = "HTTP" },
        { protocol = "tcp", port_min = 443, port_max = 443, cidr = "0.0.0.0/0", description = "HTTPS" }
      ]
    }
    app = {
      description = "Application tier — only from web tier"
      ingress_rules = [
        {
          protocol      = "tcp"
          port_min      = 8080
          port_max      = 8080
          remote_sg_key = "web"
          description   = "App port from web tier"
        }
      ]
    }
    db = {
      description = "Database tier — only from app tier"
      ingress_rules = [
        {
          protocol      = "tcp"
          port_min      = 5432
          port_max      = 5432
          remote_sg_key = "app"
          description   = "PostgreSQL from app tier"
        }
      ]
    }
  }
}

# ─────────────────────────────────────────────
# 3. EIP — Elastic IPs & Bandwidth
# ─────────────────────────────────────────────
module "eip" {
  source = "../../modules/eip"

  name_prefix = local.name_prefix

  shared_bandwidths      = var.eip_shared_bandwidths
  dedicated_eips         = var.eip_dedicated
  shared_eips            = var.eip_shared
  bandwidth_associations = var.eip_bandwidth_associations
  eip_associations       = var.eip_associations

  external_bandwidth_ids = var.eip_external_bandwidth_ids
  external_eip_ids       = var.eip_external_eip_ids
  external_eip_addresses = var.eip_external_eip_addresses

  depends_on = [module.network]
}

# ─────────────────────────────────────────────
# 4. ECS — Web Tier
# ─────────────────────────────────────────────
module "web" {
  source = "../../modules/ecs"

  name_prefix                = "${local.name_prefix}-web"
  default_image_name         = var.image_name
  default_availability_zones = var.availability_zones
  default_key_pair           = var.key_pair_name
  default_security_group_ids = [
    module.security.security_group_ids["web"],
    module.network.default_security_group_id,
  ]
  tags          = local.common_tags
  server_groups = var.ecs_web_server_groups
  keypairs      = var.ecs_web_keypairs

  # One instance per count entry, round-robin across public subnets
  instances = {
    for i in range(var.web_instance_count) :
    format("web-%02d", i + 1) => {
      flavor_id        = var.web_flavor_id
      subnet_id        = module.network.public_subnet_id_list[i % length(module.network.public_subnet_id_list)]
      system_disk_type = var.web_system_disk_type
      system_disk_size = var.web_system_disk_size
    }
  }

  depends_on = [module.network, module.security]
}

# ─────────────────────────────────────────────
# 5. ECS — App Tier
# ─────────────────────────────────────────────
module "app" {
  source = "../../modules/ecs"

  name_prefix                = "${local.name_prefix}-app"
  default_image_name         = var.image_name
  default_availability_zones = var.availability_zones
  default_key_pair           = var.key_pair_name
  default_security_group_ids = [
    module.security.security_group_ids["app"],
    module.network.default_security_group_id,
  ]
  tags          = local.common_tags
  server_groups = var.ecs_app_server_groups
  keypairs      = var.ecs_app_keypairs

  # One instance per count entry, round-robin across private subnets
  instances = {
    for i in range(var.app_instance_count) :
    format("app-%02d", i + 1) => {
      flavor_id        = var.app_flavor_id
      subnet_id        = module.network.private_subnet_id_list[i % length(module.network.private_subnet_id_list)]
      system_disk_type = var.app_system_disk_type
      system_disk_size = var.app_system_disk_size
      data_disks = [
        { type = var.app_system_disk_type, size = var.app_data_disk_size }
      ]
    }
  }

  depends_on = [module.network, module.security]
}

# ─────────────────────────────────────────────
# 6. OBS — Object Storage Service
# ─────────────────────────────────────────────
module "obs" {
  source = "../../modules/obs"

  name_prefix = local.name_prefix
  tags        = local.common_tags

  buckets          = var.obs_buckets
  bucket_acls      = var.obs_bucket_acls
  objects          = var.obs_objects
  object_acls      = var.obs_object_acls
  bucket_policies  = var.obs_bucket_policies
  existing_buckets = var.obs_existing_buckets
}

# ─────────────────────────────────────────────
# 7. CCE — Kubernetes Cluster
# ─────────────────────────────────────────────
module "cce" {
  source = "../../modules/cce"

  name_prefix = local.name_prefix

  # Cluster settings
  cluster_flavor_id      = var.cce_cluster_flavor_id
  vpc_id                 = module.network.vpc_id
  subnet_id              = module.network.private_subnet_id_list[0]
  container_network_type = var.cce_container_network_type
  container_network_cidr = var.cce_container_network_cidr
  service_network_cidr   = var.cce_service_network_cidr
  kube_proxy_mode        = var.cce_kube_proxy_mode
  cluster_eip            = var.cce_cluster_eip
  cluster_multi_az       = var.cce_cluster_multi_az

  delete_storage_on_destroy = true
  tags                      = local.common_tags

  # Node pools
  key_pair_name = var.key_pair_name
  node_pools    = var.cce_node_pools

  # Namespaces
  namespaces = var.cce_namespaces

  depends_on = [module.network, module.security]
}

# ─────────────────────────────────────────────
# 8. GaussDB OpenGauss
# ─────────────────────────────────────────────
module "gaussdb" {
  source = "../../modules/gaussdb"

  instances           = var.gaussdb_instances
  parameter_templates = var.gaussdb_parameter_templates

  existing_instances           = var.gaussdb_existing_instances
  existing_parameter_templates = var.gaussdb_existing_parameter_templates

  depends_on = [module.network, module.security]
}

# ─────────────────────────────────────────────
# 9. RDS — Relational Database Service
# ─────────────────────────────────────────────
module "rds" {
  source = "../../modules/rds"

  instances          = var.rds_instances
  mysql_databases    = var.rds_mysql_databases
  mysql_accounts     = var.rds_mysql_accounts
  mysql_privileges   = var.rds_mysql_privileges
  pg_databases       = var.rds_pg_databases
  pg_accounts        = var.rds_pg_accounts
  pg_privileges      = var.rds_pg_privileges
  pg_plugins         = var.rds_pg_plugins
  sql_audits         = var.rds_sql_audits
  existing_instances = var.rds_existing_instances

  depends_on = [module.network, module.security]
}
