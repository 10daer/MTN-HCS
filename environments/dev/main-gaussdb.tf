###############################################################################
# GaussDB — openGauss instances and parameter templates
# Module: ../../modules/gaussdb        Values: gaussdb.auto.tfvars
#
# Inert until gaussdb.auto.tfvars defines instances: every input defaults to {}.
#
# Network ids are per-instance fields (vpc_id, subnet_id, security_group_id)
# inside gaussdb_instances. Note the AZ handling: leave availability_zone unset
# and the module auto-selects az_count AZs (default 3) — on a single-AZ stack
# like lagos-mtn-1 (az1.dc0) set availability_zone explicitly and az_count = 1.
###############################################################################

module "gaussdb" {
  source = "../../modules/gaussdb"

  # Network ids fall back to the network stack when left empty in tfvars — the
  # reference to module.network creates the dependency edge that keeps a single
  # `terraform plan` correctly ordered. An explicit value in tfvars always wins.
  instances = {
    for k, v in var.gaussdb_instances : k => merge(v, {
      vpc_id            = v.vpc_id != "" ? v.vpc_id : module.network.vpc_id
      subnet_id         = v.subnet_id != "" ? v.subnet_id : module.network.public_subnet_id_list[0]
      security_group_id = try(v.security_group_id, "") != "" ? v.security_group_id : module.network.default_security_group_id
    })
  }
  parameter_templates = var.gaussdb_parameter_templates

  # Data-source lookups for pre-existing GaussDB resources
  existing_instances           = var.gaussdb_existing_instances
  existing_parameter_templates = var.gaussdb_existing_parameter_templates

  depends_on = [module.network]
}
