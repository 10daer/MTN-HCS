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

  instances           = var.gaussdb_instances
  parameter_templates = var.gaussdb_parameter_templates

  # Data-source lookups for pre-existing GaussDB resources
  existing_instances           = var.gaussdb_existing_instances
  existing_parameter_templates = var.gaussdb_existing_parameter_templates
}
