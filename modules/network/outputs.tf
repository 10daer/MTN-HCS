###############################################################################
# Module: network – Outputs
###############################################################################

output "vpc_id" {
  description = "ID of the VPC."
  value       = hcs_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = hcs_vpc.this.cidr
}

output "public_subnet_ids" {
  description = "Map of public subnet keys to IDs."
  value       = { for k, v in hcs_vpc_subnet.public : k => v.id }
}

output "public_subnet_id_list" {
  description = "List of public subnet IDs."
  value       = [for v in hcs_vpc_subnet.public : v.id]
}

output "private_subnet_ids" {
  description = "Map of private subnet keys to IDs."
  value       = { for k, v in hcs_vpc_subnet.private : k => v.id }
}

output "private_subnet_id_list" {
  description = "List of private subnet IDs."
  value       = [for v in hcs_vpc_subnet.private : v.id]
}

output "default_security_group_id" {
  description = "ID of the default security group created by this module."
  value       = hcs_networking_secgroup.default.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway (empty string if not created)."
  value       = var.enable_nat_gateway ? hcs_nat_gateway.this[0].id : ""
}

output "nat_eip_address" {
  description = "Public IP address of the NAT gateway EIP."
  value       = var.enable_nat_gateway ? hcs_vpc_eip.nat[0].address : ""
}