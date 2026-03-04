###############################################################################
# Module: security – Outputs
###############################################################################

output "security_group_ids" {
  description = "Map of security group keys to their IDs."
  value       = { for k, v in hcs_networking_secgroup.this : k => v.id }
}

output "security_groups" {
  description = "Full map of security group resources."
  value       = hcs_networking_secgroup.this
}