###############################################################################
# Dev Environment — root module
# Orchestrates: network → security → ecs (with discovered flavor/AZ/image)
#
# Design note: like the known-good standalone config, this environment does
# NOT hardcode environment-specific values (AZ, flavor, image). It discovers
# them from the live HCS stack via data sources so the plan always references
# things that actually exist on MTN Lagos.
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
# 0. Discovery — resolve environment-specific values at plan time
#    (mirrors the standalone working config)
# ─────────────────────────────────────────────

# All availability zones in this project
data "hcs_availability_zones" "available" {}

# A flavor matching the requested vCPU / RAM, scoped to the first AZ
data "hcs_ecs_compute_flavors" "web" {
  availability_zone = data.hcs_availability_zones.available.names[0]
  cpu_core_count    = var.web_flavor_cpu
  memory_size       = var.web_flavor_memory
}

# The image, resolved by display name to its ID
data "hcs_ims_images" "web" {
  name = var.image_name
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
  availability_zones   = data.hcs_availability_zones.available.names
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
# 3. ECS — Web Tier (with self-created EIP)
# ─────────────────────────────────────────────
module "web" {
  source = "../../modules/ecs"

  name_prefix                = "${local.name_prefix}-web"
  default_image_name         = var.image_name
  default_availability_zones = [data.hcs_availability_zones.available.names[0]]
  default_security_group_ids = [
    module.security.security_group_ids["server"],
    module.network.default_security_group_id,
  ]
  tags = local.common_tags

  instances = {
    "web-01" = {
      # Discovered values — never hardcoded (see design note above)
      flavor_id         = data.hcs_ecs_compute_flavors.web.ids[0]
      image_id          = data.hcs_ims_images.web.images[0].id
      availability_zone = data.hcs_availability_zones.available.names[0]
      subnet_id         = module.network.public_subnet_id_list[0]

      system_disk_type = var.web_system_disk_type
      system_disk_size = var.web_system_disk_size

      # Create + associate a fresh EIP through the module, exactly like the
      # standalone config's hcs_vpc_eip → hcs_ecs_compute_eip_associate pair.
      assign_eip         = true
      eip_type           = var.eip_type
      eip_bandwidth_size = var.web_eip_bandwidth_size
    }
  }

  depends_on = [module.network, module.security]
}
