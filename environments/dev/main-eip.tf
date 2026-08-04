###############################################################################
# EIP — Elastic IPs, shared bandwidths, associations
# Module: ../../modules/eip            Values: eip.auto.tfvars
#
# Inert until eip.auto.tfvars defines something: every input is a map that
# defaults to {}.
#
# Note: the web tier's EIP is created by the ecs module (assign_eip = true in
# main-ecs.tf), not here. Use this stack for EIPs that outlive an instance, or
# for shared-bandwidth setups.
###############################################################################

module "eip" {
  source = "../../modules/eip"

  name_prefix = local.name_prefix

  shared_bandwidths      = var.eip_shared_bandwidths
  dedicated_eips         = var.eip_dedicated
  shared_eips            = var.eip_shared
  bandwidth_associations = var.eip_bandwidth_associations
  eip_associations       = var.eip_associations

  # Ids of bandwidths / EIPs created outside this module
  external_bandwidth_ids = var.eip_external_bandwidth_ids
  external_eip_ids       = var.eip_external_eip_ids
  external_eip_addresses = var.eip_external_eip_addresses
}
