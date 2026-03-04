###############################################################################
# Module: ecs – Outputs
###############################################################################

# ── Instances ────────────────────────────────
output "instance_ids" {
  description = "Map of instance keys to their IDs."
  value       = { for k, v in hcs_ecs_compute_instance.this : k => v.id }
}

output "instance_names" {
  description = "Map of instance keys to their names."
  value       = { for k, v in hcs_ecs_compute_instance.this : k => v.name }
}

output "instance_status" {
  description = "Map of instance keys to their status."
  value       = { for k, v in hcs_ecs_compute_instance.this : k => v.status }
}

output "private_ips" {
  description = "Map of instance keys to primary private IPv4 addresses."
  value       = { for k, v in hcs_ecs_compute_instance.this : k => v.access_ip_v4 }
}

output "public_ips" {
  description = "Map of instance keys to public IPs (populated when auto-EIP is set on the instance)."
  value       = { for k, v in hcs_ecs_compute_instance.this : k => v.public_ip }
}

output "eip_addresses" {
  description = "Map of instance keys to EIP addresses (only for instances with assign_eip = true)."
  value       = { for k, v in hcs_vpc_eip.this : k => v.address }
}

output "system_disk_ids" {
  description = "Map of instance keys to their system disk IDs."
  value       = { for k, v in hcs_ecs_compute_instance.this : k => v.system_disk_id }
}

output "network_details" {
  description = "Map of instance keys to full network attachment details."
  value       = { for k, v in hcs_ecs_compute_instance.this : k => v.network }
}

output "volume_attached" {
  description = "Map of instance keys to attached volume details."
  value       = { for k, v in hcs_ecs_compute_instance.this : k => v.volume_attached }
}

output "instance_id_list" {
  description = "Flat list of all instance IDs (useful for server group membership)."
  value       = [for v in hcs_ecs_compute_instance.this : v.id]
}

# ── Keypairs ─────────────────────────────────
output "keypair_names" {
  description = "Map of keypair keys to their names."
  value       = { for k, v in hcs_ecs_compute_keypair.this : k => v.name }
}

# ── Server Groups ────────────────────────────
output "server_group_ids" {
  description = "Map of server group keys to their IDs."
  value       = { for k, v in hcs_ecs_compute_server_group.this : k => v.id }
}

output "server_group_names" {
  description = "Map of server group keys to their names."
  value       = { for k, v in hcs_ecs_compute_server_group.this : k => v.name }
}

# ── Volume Attachments ───────────────────────
output "volume_attachment_ids" {
  description = "Map of volume attachment keys to their IDs."
  value       = { for k, v in hcs_ecs_compute_volume_attach.this : k => v.id }
}

# ── Interface Attachments ────────────────────
output "interface_attachment_ports" {
  description = "Map of interface attachment keys to their port IDs."
  value       = { for k, v in hcs_ecs_compute_interface_attach.this : k => v.port_id }
}

# ── Snapshots ────────────────────────────────
output "snapshot_ids" {
  description = "Map of snapshot keys to their IDs."
  value       = { for k, v in hcs_ecs_compute_snapshot.this : k => v.id }
}
