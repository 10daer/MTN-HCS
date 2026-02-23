###############################################################################
# Dev Environment — root module
# Orchestrates: network → security → compute → storage → iam
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
  nat_gateway_spec     = "1"    # small — sufficient for dev
  nat_bandwidth_size   = 10
  eip_type             = var.eip_type
  tags                 = local.common_tags
}

# ─────────────────────────────────────────────
# 2. Security Groups
# ─────────────────────────────────────────────
module "security" {
  source = "../../modules/security"

  name_prefix = local.name_prefix
  tags        = local.common_tags

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
        { protocol = "tcp", port_min = 80,  port_max = 80,  cidr = "0.0.0.0/0", description = "HTTP" },
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
# 3. Compute — Web Tier
# ─────────────────────────────────────────────
module "web_servers" {
  source = "../../modules/compute"

  name_prefix        = "${local.name_prefix}-web"
  instance_count     = var.web_instance_count
  flavor_id          = var.web_flavor_id
  image_name         = var.image_name
  availability_zones = var.availability_zones
  subnet_ids         = module.network.public_subnet_id_list
  security_group_ids = [
    module.security.security_group_ids["web"],
    module.network.default_security_group_id
  ]
  key_pair_name    = var.key_pair_name
  system_disk_type = "SSD"
  system_disk_size = 50
  assign_eip       = false   # ELB handles public traffic; no direct EIP needed
  tags             = merge(local.common_tags, { Tier = "web" })

  depends_on = [module.network, module.security]
}

# ─────────────────────────────────────────────
# 4. Compute — App Tier
# ─────────────────────────────────────────────
module "app_servers" {
  source = "../../modules/compute"

  name_prefix        = "${local.name_prefix}-app"
  instance_count     = var.app_instance_count
  flavor_id          = var.app_flavor_id
  image_name         = var.image_name
  availability_zones = var.availability_zones
  subnet_ids         = module.network.private_subnet_id_list
  security_group_ids = [
    module.security.security_group_ids["app"],
    module.network.default_security_group_id
  ]
  key_pair_name    = var.key_pair_name
  system_disk_type = "SSD"
  system_disk_size = 50
  data_disks       = [{ type = "SSD", size = 100 }]
  assign_eip       = false
  tags             = merge(local.common_tags, { Tier = "app" })

  depends_on = [module.network, module.security]
}

# ─────────────────────────────────────────────
# 5. Storage
# ─────────────────────────────────────────────
module "storage" {
  source = "../../modules/storage"

  name_prefix = local.name_prefix
  tags        = local.common_tags

  obs_buckets = {
    logs = {
      acl           = "private"
      storage_class = "WARM"
      versioning    = false
      lifecycle_rules = [
        { name = "expire-logs", expiration_days = 30 }
      ]
    }
    artifacts = {
      acl           = "private"
      storage_class = "STANDARD"
      versioning    = true
    }
  }
}

# ─────────────────────────────────────────────
# 6. IAM
# ─────────────────────────────────────────────
module "iam" {
  source = "../../modules/iam"

  name_prefix = local.name_prefix

  policies = {
    obs-readonly = {
      description = "OBS read-only for ${local.name_prefix}"
      statements = [
        {
          Effect   = "Allow"
          Action   = ["obs:object:Get", "obs:bucket:ListBucket", "obs:bucket:GetBucketLocation"]
          Resource = ["OBS:*:*:object:${local.name_prefix}-*/*", "OBS:*:*:bucket:${local.name_prefix}-*"]
        }
      ]
    }
  }

  agencies = {
    ecs-obs-rw = {
      description        = "Allow ECS instances to write to OBS"
      delegated_service  = "op_svc_ecs"
      project_roles = [
        {
          project = var.project_name
          roles   = ["OBS OperateAccess"]
        }
      ]
    }
  }
}
