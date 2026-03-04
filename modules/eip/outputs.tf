###############################################################################
# Module: eip – Outputs
###############################################################################

# ── Shared Bandwidths ────────────────────────
output "bandwidth_ids" {
  description = "Map of shared bandwidth keys to their IDs."
  value       = { for k, v in hcs_vpc_bandwidth.this : k => v.id }
}

output "bandwidth_names" {
  description = "Map of shared bandwidth keys to their names."
  value       = { for k, v in hcs_vpc_bandwidth.this : k => v.name }
}

output "bandwidth_status" {
  description = "Map of shared bandwidth keys to their status."
  value       = { for k, v in hcs_vpc_bandwidth.this : k => v.status }
}

output "bandwidth_publicips" {
  description = "Map of shared bandwidth keys to their attached EIP list."
  value       = { for k, v in hcs_vpc_bandwidth.this : k => v.publicips }
}

# ── Dedicated EIPs ──────────────────────────
output "dedicated_eip_ids" {
  description = "Map of dedicated EIP keys to their IDs."
  value       = { for k, v in hcs_vpc_eip.dedicated : k => v.id }
}

output "dedicated_eip_addresses" {
  description = "Map of dedicated EIP keys to their IPv4 addresses."
  value       = { for k, v in hcs_vpc_eip.dedicated : k => v.address }
}

output "dedicated_eip_status" {
  description = "Map of dedicated EIP keys to their status."
  value       = { for k, v in hcs_vpc_eip.dedicated : k => v.status }
}

# ── Shared EIPs ─────────────────────────────
output "shared_eip_ids" {
  description = "Map of shared EIP keys to their IDs."
  value       = { for k, v in hcs_vpc_eip.shared : k => v.id }
}

output "shared_eip_addresses" {
  description = "Map of shared EIP keys to their IPv4 addresses."
  value       = { for k, v in hcs_vpc_eip.shared : k => v.address }
}

output "shared_eip_status" {
  description = "Map of shared EIP keys to their status."
  value       = { for k, v in hcs_vpc_eip.shared : k => v.status }
}

# ── All EIPs (merged convenience maps) ──────
output "all_eip_ids" {
  description = "Merged map of all EIP keys (dedicated + shared + external) to IDs."
  value       = local.resolved_eip_ids
}

output "all_eip_addresses" {
  description = "Merged map of all EIP keys (dedicated + shared + external) to IPv4 addresses."
  value       = local.resolved_eip_addresses
}

# ── Bandwidth Associations ──────────────────
output "bandwidth_association_ids" {
  description = "Map of bandwidth association keys to their IDs (bandwidth_id/eip_id)."
  value       = { for k, v in hcs_vpc_bandwidth_associate.this : k => v.id }
}

# ── EIP Associations ────────────────────────
output "eip_association_ids" {
  description = "Map of EIP association keys to their IDs."
  value       = { for k, v in hcs_vpc_eip_associate.this : k => v.id }
}

output "eip_association_status" {
  description = "Map of EIP association keys to their status (should be BOUND)."
  value       = { for k, v in hcs_vpc_eip_associate.this : k => v.status }
}

output "eip_association_mac_addresses" {
  description = "Map of EIP association keys to MAC addresses of bound ports."
  value       = { for k, v in hcs_vpc_eip_associate.this : k => v.mac_address }
}
