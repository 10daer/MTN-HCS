###############################################################################
# Dev Environment — outputs
#
# The network ids here are what you paste into the other stacks' tfvars
# (rds_instances[*].subnet_id, cce_subnet_id, ecs_web_subnet_id, …):
#
#   terraform output network_ids
#
# Outputs for the gated stacks (cce, vdc) resolve to null while they are off.
###############################################################################

# ─────────────────────────────────────────────
# Network — copy these into the other stacks' tfvars
# ─────────────────────────────────────────────
output "network_ids" {
  description = "VPC, subnet and security group ids for wiring the other stacks."
  value = {
    vpc_id             = module.network.vpc_id
    vpc_cidr           = module.network.vpc_cidr
    public_subnet_ids  = module.network.public_subnet_ids
    private_subnet_ids = module.network.private_subnet_ids
    default_sg_id      = module.network.default_security_group_id
    security_group_ids = module.security.security_group_ids
  }
}

output "nat_gateway_id" {
  description = "NAT gateway id (null when enable_nat_gateway = false)."
  value       = module.network.nat_gateway_id
}

output "nat_eip_address" {
  description = "Public IP of the NAT gateway EIP (null when NAT is disabled)."
  value       = module.network.nat_eip_address
}

# ─────────────────────────────────────────────
# Discovery — what the data sources resolved to
# ─────────────────────────────────────────────
output "discovered" {
  description = "Values resolved from the live HCS stack at plan time."
  value = {
    availability_zones = data.hcs_availability_zones.available.names
    web_flavor_id      = try(data.hcs_ecs_compute_flavors.web.ids[0], null)
    web_image_id       = try(data.hcs_ims_images.web.images[0].id, null)
  }
}

# ─────────────────────────────────────────────
# ECS — web tier
# ─────────────────────────────────────────────
output "web_instance_ids" {
  description = "Web tier instance ids, keyed by instance name."
  value       = module.web.instance_ids
}

output "web_private_ips" {
  description = "Web tier private IPv4 addresses."
  value       = module.web.private_ips
}

output "web_eip_addresses" {
  description = "Web tier EIPs created by the ecs module."
  value       = module.web.eip_addresses
}

# ─────────────────────────────────────────────
# EIP
# ─────────────────────────────────────────────
output "eip_addresses" {
  description = "All EIP addresses managed by the eip stack."
  value       = module.eip.all_eip_addresses
}

output "eip_bandwidth_ids" {
  description = "Shared bandwidth ids managed by the eip stack."
  value       = module.eip.bandwidth_ids
}

# ─────────────────────────────────────────────
# CCE (null while cce_enabled = false)
# ─────────────────────────────────────────────
output "cce_cluster_id" {
  description = "CCE cluster id."
  value       = try(module.cce[0].cluster_id, null)
}

output "cce_node_pool_ids" {
  description = "CCE node pool ids."
  value       = try(module.cce[0].node_pool_ids, null)
}

output "cce_kube_config" {
  description = "Raw kubeconfig for the CCE cluster."
  value       = try(module.cce[0].kube_config_raw, null)
  sensitive   = true
}

# ─────────────────────────────────────────────
# RDS
# ─────────────────────────────────────────────
output "rds_instance_ids" {
  description = "RDS instance ids, keyed by logical name."
  value       = module.rds.instance_ids
}

output "rds_private_ips" {
  description = "RDS private connection addresses."
  value       = module.rds.instance_private_ips
}

# ─────────────────────────────────────────────
# GaussDB
# ─────────────────────────────────────────────
output "gaussdb_instance_ids" {
  description = "GaussDB instance ids, keyed by logical name."
  value       = module.gaussdb.instance_ids
}

output "gaussdb_endpoints" {
  description = "GaussDB connection endpoints."
  value       = module.gaussdb.instance_endpoints
}

# ─────────────────────────────────────────────
# OBS
# ─────────────────────────────────────────────
output "obs_bucket_names" {
  description = "OBS bucket names, keyed by logical name."
  value       = module.obs.bucket_names
}

output "obs_bucket_domain_names" {
  description = "OBS bucket domain names for client configuration."
  value       = module.obs.bucket_domain_names
}

# ─────────────────────────────────────────────
# VDC (null while vdc_id is unset)
# ─────────────────────────────────────────────
output "vdc_user_ids" {
  description = "VDC user ids, keyed by logical name."
  value       = try(module.vdc[0].user_ids, null)
}

output "vdc_group_ids" {
  description = "VDC group ids, keyed by logical name."
  value       = try(module.vdc[0].group_ids, null)
}

output "vdc_project_ids" {
  description = "VDC project (resource space) ids."
  value       = try(module.vdc[0].project_ids, null)
}
