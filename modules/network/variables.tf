###############################################################################
# Module: network – Input Variables
###############################################################################

variable "name_prefix" {
  description = "Prefix used to name all network resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets."
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets."
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "List of availability zones for subnet placement (round-robin)."
  type        = list(string)
}

variable "dns_servers" {
  description = "List of DNS server addresses for subnets."
  type        = list(string)
  default     = ["100.125.4.25"]
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT gateway for private subnet egress."
  type        = bool
  default     = false
}

variable "nat_gateway_spec" {
  description = "NAT gateway specification (1 = small, 2 = medium, 3 = large, 4 = extra-large)."
  type        = string
  default     = "1"
}

variable "nat_bandwidth_size" {
  description = "Bandwidth size in Mbit/s for the NAT gateway EIP."
  type        = number
  default     = 10
}

variable "eip_type" {
  description = "EIP publicip type — depends on HCS environment."
  type        = string
  default     = "eip"
}