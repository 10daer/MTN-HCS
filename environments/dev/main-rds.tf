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

  instances = var.rds_instances

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
}
