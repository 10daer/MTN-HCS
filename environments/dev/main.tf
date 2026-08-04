###############################################################################
# Dev Environment — shared root
#
# This file holds ONLY what every service stack shares: naming, common tags,
# and the discovery data sources that resolve environment-specific values
# (AZ, flavor, image) from the live HCS stack at plan time.
#
# Each service is wired in its own file so it can be read and changed in
# isolation, with its values in a matching *.auto.tfvars:
#
#   main-network.tf   → network.auto.tfvars    (VPC, subnets, NAT, default SG)
#   main-security.tf  → security.auto.tfvars   (security groups + rules)
#   main-eip.tf       → eip.auto.tfvars        (EIPs, shared bandwidth)
#   main-ecs.tf       → ecs.auto.tfvars        (ECS instances, keypairs)
#   main-cce.tf       → cce.auto.tfvars        (CCE cluster, node pools, ns)
#   main-rds.tf       → rds.auto.tfvars        (RDS MySQL / PostgreSQL)
#   main-gaussdb.tf   → gaussdb.auto.tfvars    (GaussDB openGauss)
#   main-obs.tf       → obs.auto.tfvars        (OBS buckets, objects, policies)
#   main-vdc.tf       → vdc.auto.tfvars        (VDC users, groups, roles)
#
# All of it is ONE Terraform root and ONE state file. Every *.auto.tfvars is
# loaded automatically on every terraform command, so a plain
# `terraform plan` / `terraform apply` always sees the complete picture —
# there is no -var-file to remember and no way to half-configure the stack.
#
# Every stack except network is inert until its tfvars are filled in: the
# map-driven modules (eip, rds, gaussdb, obs, vdc) create nothing from an
# empty map, and cce is behind cce_enabled.
#
# Design note: this environment does NOT hardcode environment-specific values
# (AZ, flavor, image). It discovers them from the live HCS stack via data
# sources so the plan always references things that exist on MTN Lagos.
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
