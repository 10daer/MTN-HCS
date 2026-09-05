###############################################################################
# RDS — MySQL / PostgreSQL instances, databases, accounts, privileges, audit
# Module: ../../modules/rds            Values: rds.auto.tfvars
#
# Inert until rds.auto.tfvars defines instances: every input defaults to {}.
#
# Network ids are per-instance fields (vpc_id, subnet_id, security_group_id)
# inside rds_instances, so each instance can sit wherever you need. Copy the
# ids from `terraform output` after the network stack applies.
###############################################################################

module "rds" {
  source = "../../modules/rds"

  # Network ids fall back to the network stack when left empty in tfvars.
  #
  # This is what makes a single `terraform plan` correct: referencing
  # module.network here creates a real dependency edge, so Terraform waits for
  # the VPC instead of racing it. With hardcoded ids there is no edge, RDS is
  # scheduled in parallel with the VPC, and on a fresh build the pasted id is
  # always stale — "DBS.200503 VPC ID not found".
  #
  # Set any of the three explicitly in rds.auto.tfvars to pin an instance to a
  # subnet or SG this state does not manage; an explicit value always wins.
  instances = {
    for k, v in var.rds_instances : k => merge(v, {
      vpc_id            = try(v.vpc_id, "") != "" ? v.vpc_id : module.network.vpc_id
      subnet_id         = try(v.subnet_id, "") != "" ? v.subnet_id : module.network.public_subnet_id_list[0]
      security_group_id = try(v.security_group_id, "") != "" ? v.security_group_id : module.network.default_security_group_id
    })
  }

  # MySQL
  mysql_databases  = var.rds_mysql_databases
  mysql_accounts   = var.rds_mysql_accounts
  mysql_privileges = var.rds_mysql_privileges

  # PostgreSQL
  pg_databases  = var.rds_pg_databases
  pg_accounts   = var.rds_pg_accounts
  pg_privileges = var.rds_pg_privileges
  pg_plugins    = var.rds_pg_plugins

  # Audit
  sql_audits = var.rds_sql_audits

  # Must stay {} — the provider has no hcs_rds_instance data source.
  existing_instances = var.rds_existing_instances

  depends_on = [module.network]
}
