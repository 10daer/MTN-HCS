###############################################################################
# Module: eip
#
# Manages EIP & Bandwidth resources on Huawei Cloud Stack:
#   - Shared Bandwidths          (hcs_vpc_bandwidth)
#   - EIPs (dedicated or shared) (hcs_vpc_eip)
#   - Bandwidth Associations     (hcs_vpc_bandwidth_associate)
#   - EIP Associations           (hcs_vpc_eip_associate)
#
# Provider: huaweicloud/hcs (Huawei Cloud Stack)
###############################################################################

# ─────────────────────────────────────────────
# 1. Shared Bandwidths
# ─────────────────────────────────────────────
resource "hcs_vpc_bandwidth" "this" {
  for_each = var.shared_bandwidths

  name                  = each.value.name
  size                  = each.value.size
  enterprise_project_id = try(each.value.enterprise_project_id, null)

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

# ─────────────────────────────────────────────
# 2. EIPs — Dedicated Bandwidth (PER)
# ─────────────────────────────────────────────
resource "hcs_vpc_eip" "dedicated" {
  for_each = var.dedicated_eips

  publicip {
    type       = try(each.value.ip_type, "eip")
    ip_address = try(each.value.ip_address, null)
  }

  bandwidth {
    share_type = "PER"
    name       = try(each.value.bandwidth_name, "${var.name_prefix}-${each.key}-bw")
    size       = each.value.bandwidth_size
  }

  name                  = try(each.value.name, null)
  enterprise_project_id = try(each.value.enterprise_project_id, null)

  timeouts {
    create = "10m"
    update = "5m"
    delete = "5m"
  }
}

# ─────────────────────────────────────────────
# 3. EIPs — Shared Bandwidth (WHOLE)
# ─────────────────────────────────────────────
resource "hcs_vpc_eip" "shared" {
  for_each = var.shared_eips

  publicip {
    type       = try(each.value.ip_type, "eip")
    ip_address = try(each.value.ip_address, null)
  }

  bandwidth {
    share_type = "WHOLE"
    id         = local.resolved_bandwidth_ids[each.value.bandwidth_key]
  }

  name                  = try(each.value.name, null)
  enterprise_project_id = try(each.value.enterprise_project_id, null)

  timeouts {
    create = "10m"
    update = "5m"
    delete = "5m"
  }
}

# ─────────────────────────────────────────────
# 4. Bandwidth Associations
#    (Attach an existing dedicated EIP to a shared bandwidth)
# ─────────────────────────────────────────────
resource "hcs_vpc_bandwidth_associate" "this" {
  for_each = var.bandwidth_associations

  bandwidth_id   = local.resolved_bandwidth_ids[each.value.bandwidth_key]
  eip_id         = local.resolved_eip_ids[each.value.eip_key]
  bandwidth_size = try(each.value.fallback_bandwidth_size, null)

  # When associating a TF-managed dedicated EIP, the bandwidth block changes.
  # The dedicated EIP resource should have lifecycle { ignore_changes = [bandwidth] }.
}

# ─────────────────────────────────────────────
# 5. EIP Associations (bind EIP to port / fixed IP)
# ─────────────────────────────────────────────
resource "hcs_vpc_eip_associate" "this" {
  for_each = var.eip_associations

  public_ip  = local.resolved_eip_addresses[each.value.eip_key]
  port_id    = try(each.value.port_id, null)
  fixed_ip   = try(each.value.fixed_ip, null)
  network_id = try(each.value.network_id, null)

  timeouts {
    create = "5m"
    delete = "5m"
  }
}

# ─────────────────────────────────────────────
# Locals — unified ID & address resolution
# ─────────────────────────────────────────────
locals {
  # Bandwidth IDs: managed + external
  resolved_bandwidth_ids = merge(
    { for k, v in hcs_vpc_bandwidth.this : k => v.id },
    var.external_bandwidth_ids,
  )

  # EIP IDs: dedicated + shared + external
  resolved_eip_ids = merge(
    { for k, v in hcs_vpc_eip.dedicated : k => v.id },
    { for k, v in hcs_vpc_eip.shared : k => v.id },
    var.external_eip_ids,
  )

  # EIP addresses: dedicated + shared + external
  resolved_eip_addresses = merge(
    { for k, v in hcs_vpc_eip.dedicated : k => v.address },
    { for k, v in hcs_vpc_eip.shared : k => v.address },
    var.external_eip_addresses,
  )
}
