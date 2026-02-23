###############################################################################
# Module: network
# Creates VPC, subnets (public/private), security groups, EIP, NAT Gateway,
# and an Elastic Load Balancer (shared, optional).
###############################################################################

# ─────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────
resource "huaweicloud_vpc" "this" {
  name        = "${var.name_prefix}-vpc"
  cidr        = var.vpc_cidr
  description = "Managed by Terraform — ${var.name_prefix}"
  tags        = var.tags
}

# ─────────────────────────────────────────────
# Public Subnets
# ─────────────────────────────────────────────
resource "huaweicloud_vpc_subnet" "public" {
  for_each = { for idx, cidr in var.public_subnet_cidrs :
    "public-${idx + 1}" => { cidr = cidr, az = var.availability_zones[idx % length(var.availability_zones)] }
  }

  name              = "${var.name_prefix}-${each.key}"
  cidr              = each.value.cidr
  gateway_ip        = cidrhost(each.value.cidr, 1)
  vpc_id            = huaweicloud_vpc.this.id
  availability_zone = each.value.az
  dns_list          = var.dns_servers
  tags              = merge(var.tags, { Tier = "public" })
}

# ─────────────────────────────────────────────
# Private Subnets
# ─────────────────────────────────────────────
resource "huaweicloud_vpc_subnet" "private" {
  for_each = { for idx, cidr in var.private_subnet_cidrs :
    "private-${idx + 1}" => { cidr = cidr, az = var.availability_zones[idx % length(var.availability_zones)] }
  }

  name              = "${var.name_prefix}-${each.key}"
  cidr              = each.value.cidr
  gateway_ip        = cidrhost(each.value.cidr, 1)
  vpc_id            = huaweicloud_vpc.this.id
  availability_zone = each.value.az
  dns_list          = var.dns_servers
  tags              = merge(var.tags, { Tier = "private" })
}

# ─────────────────────────────────────────────
# EIP for NAT Gateway
# ─────────────────────────────────────────────
resource "huaweicloud_vpc_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  publicip {
    type = var.eip_type
  }
  bandwidth {
    name        = "${var.name_prefix}-nat-bw"
    size        = var.nat_bandwidth_size
    share_type  = "PER"
    charge_mode = "traffic"
  }
  tags = merge(var.tags, { Purpose = "nat-gateway" })
}

# ─────────────────────────────────────────────
# NAT Gateway
# ─────────────────────────────────────────────
resource "huaweicloud_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  name      = "${var.name_prefix}-nat"
  spec      = var.nat_gateway_spec
  vpc_id    = huaweicloud_vpc.this.id
  subnet_id = values(huaweicloud_vpc_subnet.public)[0].id
  tags      = var.tags
}

resource "huaweicloud_nat_snat_rule" "private_subnets" {
  for_each = var.enable_nat_gateway ? huaweicloud_vpc_subnet.private : {}

  nat_gateway_id = huaweicloud_nat_gateway.this[0].id
  floating_ip_id = huaweicloud_vpc_eip.nat[0].id
  subnet_id      = each.value.id
}

# ─────────────────────────────────────────────
# Default Security Group (baseline deny + managed egress)
# ─────────────────────────────────────────────
resource "huaweicloud_networking_secgroup" "default" {
  name                 = "${var.name_prefix}-default-sg"
  description          = "Default security group — managed by Terraform"
  delete_default_rules = true
  tags                 = var.tags
}

# Allow all egress (standard)
resource "huaweicloud_networking_secgroup_rule" "egress_all" {
  security_group_id = huaweicloud_networking_secgroup.default.id
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
}

# Allow intra-VPC communication
resource "huaweicloud_networking_secgroup_rule" "ingress_vpc" {
  security_group_id = huaweicloud_networking_secgroup.default.id
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.vpc_cidr
}
