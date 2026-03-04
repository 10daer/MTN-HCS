###############################################################################
# Module: eip – Input Variables
#
# Covers shared bandwidths, dedicated EIPs, shared-bandwidth EIPs,
# bandwidth associations, and EIP-to-port/IP associations.
###############################################################################

# ─────────────────────────────────────────────
# Module-level defaults
# ─────────────────────────────────────────────
variable "name_prefix" {
  description = "Prefix prepended to auto-named resources (bandwidth names, EIP bandwidth names)."
  type        = string
}

# ─────────────────────────────────────────────
# Shared Bandwidths
# ─────────────────────────────────────────────
variable "shared_bandwidths" {
  description = <<-EOT
    Map of shared bandwidth resources. Key = logical name.

    Fields:
      name – (Required) 1-64 chars.
      size – (Required) 5-2000 Mbit/s.
      enterprise_project_id – (Optional).
  EOT
  type = map(object({
    name                  = string
    size                  = number
    enterprise_project_id = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.shared_bandwidths :
      v.size >= 5 && v.size <= 2000
    ])
    error_message = "Shared bandwidth size must be 5-2000 Mbit/s."
  }
}

# ─────────────────────────────────────────────
# EIPs — Dedicated Bandwidth (PER)
# ─────────────────────────────────────────────
variable "dedicated_eips" {
  description = <<-EOT
    Map of EIPs with dedicated (PER) bandwidth. Key = logical name.

    Fields:
      bandwidth_size – (Required) 1-300 Mbit/s.
      bandwidth_name – (Optional) Name for the dedicated bandwidth; defaults to "{name_prefix}-{key}-bw".
      ip_type        – (Optional) Public IP type; default "eip".
      ip_address     – (Optional) Request a specific IPv4 address.
      name           – (Optional) EIP resource name, 1-64 chars.
      enterprise_project_id – (Optional).
  EOT
  type = map(object({
    bandwidth_size        = number
    bandwidth_name        = optional(string)
    ip_type               = optional(string, "eip")
    ip_address            = optional(string)
    name                  = optional(string)
    enterprise_project_id = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.dedicated_eips :
      v.bandwidth_size >= 1 && v.bandwidth_size <= 300
    ])
    error_message = "Dedicated EIP bandwidth_size must be 1-300 Mbit/s."
  }
}

# ─────────────────────────────────────────────
# EIPs — Shared Bandwidth (WHOLE)
# ─────────────────────────────────────────────
variable "shared_eips" {
  description = <<-EOT
    Map of EIPs that join a shared bandwidth. Key = logical name.

    Fields:
      bandwidth_key – (Required) Key from var.shared_bandwidths or var.external_bandwidth_ids.
      ip_type       – (Optional) Default "eip".
      ip_address    – (Optional) Request a specific IPv4.
      name          – (Optional) EIP resource name.
      enterprise_project_id – (Optional).
  EOT
  type = map(object({
    bandwidth_key         = string
    ip_type               = optional(string, "eip")
    ip_address            = optional(string)
    name                  = optional(string)
    enterprise_project_id = optional(string)
  }))
  default = {}
}

# ─────────────────────────────────────────────
# Bandwidth Associations
# (move an existing dedicated EIP into a shared bandwidth)
# ─────────────────────────────────────────────
variable "bandwidth_associations" {
  description = <<-EOT
    Map of bandwidth-association bindings. Key = logical name.

    Fields:
      bandwidth_key          – Key from var.shared_bandwidths or var.external_bandwidth_ids.
      eip_key                – Key from var.dedicated_eips, var.shared_eips, or var.external_eip_ids.
      fallback_bandwidth_size – (Optional) Dedicated BW size on removal (default 5 Mbit/s).
  EOT
  type = map(object({
    bandwidth_key           = string
    eip_key                 = string
    fallback_bandwidth_size = optional(number, 5)
  }))
  default = {}
}

# ─────────────────────────────────────────────
# EIP Associations (bind EIP to port or fixed IP)
# ─────────────────────────────────────────────
variable "eip_associations" {
  description = <<-EOT
    Map of EIP-to-port/IP bindings. Key = logical name.

    Fields:
      eip_key    – Key from var.dedicated_eips, var.shared_eips, or var.external_eip_addresses.
      port_id    – (Optional) Port ID to bind (preferred over fixed_ip + network_id).
      fixed_ip   – (Optional) Private IPv4 to bind.
      network_id – (Optional) Required when fixed_ip is used.

    Constraint: provide either port_id OR (fixed_ip + network_id).
  EOT
  type = map(object({
    eip_key    = string
    port_id    = optional(string)
    fixed_ip   = optional(string)
    network_id = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.eip_associations :
      (v.port_id != null) || (v.fixed_ip != null && v.network_id != null)
    ])
    error_message = "Each EIP association must specify either port_id or both fixed_ip and network_id."
  }
}

# ─────────────────────────────────────────────
# External references (IDs from outside this module)
# ─────────────────────────────────────────────
variable "external_bandwidth_ids" {
  description = "Map of logical key → bandwidth ID for bandwidths managed outside this module."
  type        = map(string)
  default     = {}
}

variable "external_eip_ids" {
  description = "Map of logical key → EIP ID for EIPs managed outside this module."
  type        = map(string)
  default     = {}
}

variable "external_eip_addresses" {
  description = "Map of logical key → EIP IPv4 address for EIPs managed outside this module."
  type        = map(string)
  default     = {}
}
