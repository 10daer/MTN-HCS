# ─────────────────────────────────────────────
# HCS Provider / Connection
# ─────────────────────────────────────────────
variable "hcs_auth_url" {
  description = "IAM endpoint for private HCS. e.g. https://iam.hcs.example.com/v3"
  type        = string
}

variable "region" {
  description = "HCS region name"
  type        = string
}

variable "domain_name" {
  description = "HCS account domain name"
  type        = string
}

variable "project_name" {
  description = "HCS project name (maps to a region project)"
  type        = string
}

variable "skip_tls_verify" {
  description = "Skip TLS verification for self-signed certs on private HCS"
  type        = bool
  default     = false
}

# ─────────────────────────────────────────────
# Resource Naming & Tagging
# ─────────────────────────────────────────────
variable "project" {
  description = "Project name — used in resource names and tags"
  type        = string
}

variable "environment" {
  description = "Environment name: dev, staging, prod"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Team or person owning these resources"
  type        = string
}

# ─────────────────────────────────────────────
# Network
# ─────────────────────────────────────────────
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.10.0/24", "10.10.11.0/24"]
}

variable "availability_zones" {
  type = list(string)
}

variable "dns_servers" {
  type    = list(string)
  default = ["100.125.4.25"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

variable "eip_type" {
  description = "EIP type. Depends on HCS environment bandwidth profile."
  type        = string
  default     = "5_bgp"
}

variable "trusted_ssh_cidr" {
  description = "CIDR allowed to SSH to bastion. Restrict tightly."
  type        = string
}

# ─────────────────────────────────────────────
# Compute
# ─────────────────────────────────────────────
variable "key_pair_name" {
  description = "Pre-existing SSH key pair in HCS"
  type        = string
}

variable "image_name" {
  description = "Public image name filter"
  type        = string
  default     = "Ubuntu 22.04 server 64bit"
}

variable "web_instance_count" {
  type    = number
  default = 2
}

variable "web_flavor_id" {
  description = "Flavor for web tier instances e.g. c6.large.2"
  type        = string
  default     = "c6.large.2"
}

variable "app_instance_count" {
  type    = number
  default = 2
}

variable "app_flavor_id" {
  description = "Flavor for app tier instances"
  type        = string
  default     = "c6.xlarge.2"
}
