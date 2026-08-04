###############################################################################
# Security — security groups and their rules
# Module: ../../modules/security       Values: security.auto.tfvars
#
# The group definitions live entirely in security.auto.tfvars (which ships with
# this environment's existing "server" group, unchanged). The module names each
# group "<name_prefix>-<key>-sg" and adds an allow-all egress rule.
###############################################################################

module "security" {
  source = "../../modules/security"

  name_prefix     = local.name_prefix
  security_groups = var.security_groups
}
