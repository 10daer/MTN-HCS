###############################################################################
# Module: ecs – Input Variables
#
# Covers all ECS resources: instances, keypairs, server groups,
# EIP associations, extra volume attachments, interface attachments,
# and snapshots.
###############################################################################

# ─────────────────────────────────────────────
# Module-level defaults (applied when an instance
# does not supply its own override)
# ─────────────────────────────────────────────
variable "name_prefix" {
  description = "Prefix prepended to auto-named resources in this module call."
  type        = string
}

variable "default_image_name" {
  description = "Default image name filter when an instance omits image_id and image_name."
  type        = string
  default     = "Ubuntu 22.04 server 64bit"
}

variable "default_availability_zones" {
  description = "Default list of AZs used for instances that omit availability_zone."
  type        = list(string)
  default     = []
}

variable "default_security_group_ids" {
  description = "Default security group IDs merged into every instance's security_group_ids."
  type        = list(string)
  default     = []
}

variable "default_key_pair" {
  description = "Default SSH key pair name; overridden per instance."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all instances in this module call."
  type        = map(string)
  default     = {}
}

# ─────────────────────────────────────────────
# Keypairs
# ─────────────────────────────────────────────
variable "keypairs" {
  description = <<-EOT
    Map of SSH keypairs to manage. Key = logical name.

    Fields:
      name     – (Required) Keypair name.
      key_file – (Optional) Path to write the private key file locally.
      public_key – (Optional) Import an existing public key string.
  EOT
  type = map(object({
    name       = string
    key_file   = optional(string)
    public_key = optional(string)
  }))
  default = {}
}

# ─────────────────────────────────────────────
# Server Groups (anti-affinity / affinity)
# ─────────────────────────────────────────────
variable "server_groups" {
  description = <<-EOT
    Map of ECS server groups. Key = logical name.

    Fields:
      name     – (Required) Server group name.
      policies – (Required) List: ["anti-affinity"] or ["affinity"].
  EOT
  type = map(object({
    name     = string
    policies = list(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.server_groups :
      alltrue([for p in v.policies : contains(["anti-affinity", "affinity"], p)])
    ])
    error_message = "Server group policies must be 'anti-affinity' or 'affinity'."
  }
}

# ─────────────────────────────────────────────
# ECS Instances
# ─────────────────────────────────────────────
variable "instances" {
  description = <<-EOT
    Map of ECS instances to create. Key = logical name.

    Required fields:
      flavor_id         – Flavor / instance type.
      subnet_id         – Primary network subnet ID.

    Optional fields:
      name              – Override resource name (defaults to "{name_prefix}-{key}").
      image_id          – Explicit image ID (takes priority over image_name).
      image_name        – Image name filter; falls back to var.default_image_name.
      availability_zone – AZ string; falls back to first in var.default_availability_zones.
      security_group_ids – Additional SG IDs merged with var.default_security_group_ids.
      fixed_ip_v4       – Fixed private IP for the primary NIC.
      ipv6_enable       – Enable IPv6 on primary NIC.
      source_dest_check – Enable source/dest check (default true).
      extra_networks    – List of extra NICs: { subnet_id, fixed_ip_v4, source_dest_check }.
      key_pair          – SSH key pair name; falls back to var.default_key_pair.
      admin_pass        – Root/admin password (alternative to key_pair).
      user_data         – Cloud-init user data (plain or base64).
      system_disk_type  – System disk type (default "business_type_01").
      system_disk_size  – System disk size in GB (default 40).
      system_kms_key_id – KMS key for system disk encryption.
      encrypt_cipher    – Cipher for disk encryption: "AES256-XTS".
      data_disks        – List of inline data disks: { type, size, kms_key_id?, encrypt_cipher?, snapshot_id? }.
      power_action      – "ON", "OFF", "REBOOT", "FORCE-OFF", "FORCE-REBOOT".
      assign_eip        – Create and associate an EIP (default false).
      eip_type          – EIP type (required when assign_eip = true).
      eip_bandwidth_size – EIP bandwidth Mbit/s (default 5).
      server_group_key  – Key from var.server_groups to join.
      enterprise_project_id – Enterprise project ID.
      scheduler_hints   – Scheduler hints block.
      delete_disks_on_termination – (default true).
      delete_eip_on_termination   – (default true).
  EOT
  type = map(object({
    flavor_id          = string
    subnet_id          = string
    name               = optional(string)
    image_id           = optional(string)
    image_name         = optional(string)
    availability_zone  = optional(string)
    security_group_ids = optional(list(string), [])
    fixed_ip_v4        = optional(string)
    ipv6_enable        = optional(bool, false)
    source_dest_check  = optional(bool, true)
    extra_networks = optional(list(object({
      subnet_id         = string
      fixed_ip_v4       = optional(string)
      source_dest_check = optional(bool, true)
    })), [])
    key_pair          = optional(string)
    admin_pass        = optional(string)
    user_data         = optional(string)
    system_disk_type  = optional(string, "business_type_01")
    system_disk_size  = optional(number, 40)
    system_kms_key_id = optional(string)
    encrypt_cipher    = optional(string)
    data_disks = optional(list(object({
      type           = string
      size           = number
      kms_key_id     = optional(string)
      encrypt_cipher = optional(string)
      snapshot_id    = optional(string)
    })), [])
    power_action                = optional(string)
    assign_eip                  = optional(bool, false)
    eip_type                    = optional(string)
    eip_bandwidth_size          = optional(number, 5)
    server_group_key            = optional(string)
    enterprise_project_id       = optional(string)
    delete_disks_on_termination = optional(bool, true)
    delete_eip_on_termination   = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.instances :
      v.assign_eip == false || v.eip_type != null
    ])
    error_message = "eip_type is required when assign_eip = true."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      v.power_action == null || contains(["ON", "OFF", "REBOOT", "FORCE-OFF", "FORCE-REBOOT"], v.power_action)
    ])
    error_message = "power_action must be one of: ON, OFF, REBOOT, FORCE-OFF, FORCE-REBOOT."
  }

  validation {
    condition = alltrue([
      for k, v in var.instances :
      v.encrypt_cipher == null || v.encrypt_cipher == "AES256-XTS"
    ])
    error_message = "encrypt_cipher must be 'AES256-XTS'."
  }
}

# ─────────────────────────────────────────────
# Additional Volume Attachments
# (EVS volumes managed outside this module)
# ─────────────────────────────────────────────
variable "volume_attachments" {
  description = <<-EOT
    Map of EVS volume attachments. Key = logical name.

    Fields:
      instance_key – Key from var.instances.
      volume_id    – ID of the EVS volume to attach.
      device       – Device path, e.g. "/dev/vdb".
  EOT
  type = map(object({
    instance_key = string
    volume_id    = string
    device       = optional(string)
  }))
  default = {}
}

# ─────────────────────────────────────────────
# Additional Interface Attachments
# ─────────────────────────────────────────────
variable "interface_attachments" {
  description = <<-EOT
    Map of secondary NIC attachments. Key = logical name.

    Fields:
      instance_key      – Key from var.instances.
      network_id        – Network UUID (mutually exclusive with port_id).
      port_id           – Existing port ID (mutually exclusive with network_id).
      fixed_ip          – Fixed IP for the new interface.
      source_dest_check – Enable source/dest check (default true).
  EOT
  type = map(object({
    instance_key      = string
    network_id        = optional(string)
    port_id           = optional(string)
    fixed_ip          = optional(string)
    source_dest_check = optional(bool, true)
  }))
  default = {}
}

# ─────────────────────────────────────────────
# Snapshots
# ─────────────────────────────────────────────
variable "snapshots" {
  description = <<-EOT
    Map of ECS instance snapshots. Key = logical name.

    Fields:
      instance_key – Key from var.instances.
      name         – Snapshot name.
  EOT
  type = map(object({
    instance_key = string
    name         = string
  }))
  default = {}
}
