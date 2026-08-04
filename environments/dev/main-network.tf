###############################################################################
# Network — VPC, subnets, NAT gateway, baseline security group
# Module: ../../modules/network        Values: network.auto.tfvars
#
# This is the foundation stack: everything else can reference its outputs
# (see outputs.tf) or take explicit ids in its own tfvars.
###############################################################################

module "network" {
  source = "../../modules/network"

  name_prefix          = local.name_prefix
  vpc_name             = var.vpc_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = data.hcs_availability_zones.available.names
  dns_servers          = var.dns_servers
  enable_nat_gateway   = var.enable_nat_gateway
  eip_type             = var.eip_type
}
