###############################################################################
# Module: network
# Creates VPC, subnets (public/private), security groups, EIP, NAT Gateway,
# and an Elastic Load Balancer (shared, optional).
#
# Provider: huaweicloud/hcs (Huawei Cloud Stack)
###############################################################################

# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────
resource "hcs_vpc" "this" {
  # VPC (router) names must be unique within the HCS project. Set vpc_name to
  # take over / sidestep a name already taken by a VPC outside this state.
  name = var.vpc_name != null ? var.vpc_name : "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr
}

# ─────────────────────────────────────────────
# Public Subnets
# ─────────────────────────────────────────────
resource "hcs_vpc_subnet" "public" {
  for_each = { for idx, cidr in var.public_subnet_cidrs :
    "public-${idx + 1}" => { cidr = cidr, az = var.availability_zones[idx % length(var.availability_zones)] }
  }

  name              = "${var.name_prefix}-${each.key}"
  cidr              = each.value.cidr
  gateway_ip        = cidrhost(each.value.cidr, 1)
  vpc_id            = hcs_vpc.this.id
  availability_zone = each.value.az
  dns_list          = var.dns_servers
}

# ─────────────────────────────────────────────
# Private Subnets
# ─────────────────────────────────────────────
resource "hcs_vpc_subnet" "private" {
  for_each = { for idx, cidr in var.private_subnet_cidrs :
    "private-${idx + 1}" => { cidr = cidr, az = var.availability_zones[idx % length(var.availability_zones)] }
  }

  name              = "${var.name_prefix}-${each.key}"
  cidr              = each.value.cidr
  gateway_ip        = cidrhost(each.value.cidr, 1)
  vpc_id            = hcs_vpc.this.id
  availability_zone = each.value.az
  dns_list          = var.dns_servers
}

# ─────────────────────────────────────────────
# EIP for NAT Gateway
# ─────────────────────────────────────────────
resource "hcs_vpc_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  publicip {
    type = var.eip_type
  }
  bandwidth {
    name       = "${var.name_prefix}-nat-bw"
    size       = var.nat_bandwidth_size
    share_type = "PER"
  }
}

# ─────────────────────────────────────────────
# NAT Gateway
# ─────────────────────────────────────────────
resource "hcs_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  name      = "${var.name_prefix}-nat"
  spec      = var.nat_gateway_spec
  vpc_id    = hcs_vpc.this.id
  subnet_id = values(hcs_vpc_subnet.public)[0].id
}

resource "hcs_nat_snat_rule" "private_subnets" {
  for_each = var.enable_nat_gateway ? hcs_vpc_subnet.private : {}

  nat_gateway_id = hcs_nat_gateway.this[0].id
  floating_ip_id = hcs_vpc_eip.nat[0].id
  subnet_id      = each.value.id
}

# ─────────────────────────────────────────────
# Default Security Group (baseline deny + managed egress)
# ─────────────────────────────────────────────
resource "hcs_networking_secgroup" "default" {
  name                 = "${var.name_prefix}-default-sg"
  description          = "Default security group — managed by Terraform"
  delete_default_rules = true
}

# Allow all egress (standard)
resource "hcs_networking_secgroup_rule" "egress_all" {
  security_group_id = hcs_networking_secgroup.default.id
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
}

# Allow intra-VPC communication
resource "hcs_networking_secgroup_rule" "ingress_vpc" {
  security_group_id = hcs_networking_secgroup.default.id
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.vpc_cidr
}
