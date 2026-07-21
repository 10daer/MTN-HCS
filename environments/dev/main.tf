###############################################################################
# Dev Environment — root module
# Orchestrates: network → security → ecs
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
  private_subnet_cidrs = []
  availability_zones   = var.availability_zones
  dns_servers          = var.dns_servers
  enable_nat_gateway   = false
  eip_type             = var.eip_type
}

# ─────────────────────────────────────────────
# 2. Security Groups
# ─────────────────────────────────────────────
module "security" {
  source = "../../modules/security"

  name_prefix = local.name_prefix

  security_groups = {
    server = {
      description = "Single server — SSH from trusted CIDR only"
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
  }
}

# ─────────────────────────────────────────────
# 3. ECS — Web Tier
# ─────────────────────────────────────────────
module "web" {
  source = "../../modules/ecs"

  name_prefix                = "${local.name_prefix}-web"
  default_image_name         = var.image_name
  default_availability_zones = var.availability_zones
  default_key_pair           = "${local.name_prefix}-web-key"
  default_security_group_ids = [
    module.security.security_group_ids["server"],
    module.network.default_security_group_id,
  ]
  tags = local.common_tags

  keypairs = {
    web = {
      name       = "${local.name_prefix}-web-key"
      public_key = var.server_ssh_public_key
    }
  }

  instances = {
    "web-01" = {
      flavor_id        = var.web_flavor_id
      subnet_id        = module.network.public_subnet_id_list[0]
      system_disk_type = var.web_system_disk_type
      system_disk_size = var.web_system_disk_size
      assign_eip       = false
    }
  }

  depends_on = [module.network, module.security]
}

# ─────────────────────────────────────────────
# 4. EIP — bind the existing pre-allocated EIP
# (Terraform-created EIPs are blocked by the "external_networks"
# error in this project — reuse the one already allocated in console.)
# ─────────────────────────────────────────────
resource "hcs_ecs_compute_eip_associate" "server" {
  public_ip   = var.server_eip_address
  instance_id = module.web.instance_ids["web-01"]

  depends_on = [module.web]
}
