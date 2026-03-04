###############################################################################
# Module: security – Input Variables
###############################################################################

variable "name_prefix" {
  description = "Prefix used to name all security group resources."
  type        = string
}

variable "security_groups" {
  description = <<-EOT
    Map of security groups to create. Each key is the SG identifier.
    Value object: { description = string, ingress_rules = list(object) }
    Each ingress rule: { protocol, port_min, port_max, cidr, remote_sg_key, description }
  EOT
  type        = any
  default     = {}
}