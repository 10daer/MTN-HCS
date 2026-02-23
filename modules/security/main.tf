###############################################################################
# Module: security
# Creates parameterized security groups with rule sets.
# Pattern: pass a list of rule objects; module creates SG + all rules.
###############################################################################

resource "huaweicloud_networking_secgroup" "this" {
  for_each = var.security_groups

  name                 = "${var.name_prefix}-${each.key}-sg"
  description          = lookup(each.value, "description", "Managed by Terraform")
  delete_default_rules = true
  tags                 = var.tags
}

# Egress — allow all by default (override with explicit rules if needed)
resource "huaweicloud_networking_secgroup_rule" "default_egress" {
  for_each = var.security_groups

  security_group_id = huaweicloud_networking_secgroup.this[each.key].id
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
}

# Ingress rules — flattened from per-SG rule list
locals {
  ingress_rules = flatten([
    for sg_key, sg in var.security_groups : [
      for idx, rule in lookup(sg, "ingress_rules", []) : {
        sg_key           = sg_key
        rule_key         = "${sg_key}-ingress-${idx}"
        protocol         = lookup(rule, "protocol", "tcp")
        port_range_min   = lookup(rule, "port_min", null)
        port_range_max   = lookup(rule, "port_max", null)
        remote_ip_prefix = lookup(rule, "cidr", null)
        remote_group_id  = lookup(rule, "remote_sg_key", null) != null ? huaweicloud_networking_secgroup.this[rule.remote_sg_key].id : null
        description      = lookup(rule, "description", "")
      }
    ]
  ])
}

resource "huaweicloud_networking_secgroup_rule" "ingress" {
  for_each = { for r in local.ingress_rules : r.rule_key => r }

  security_group_id = huaweicloud_networking_secgroup.this[each.value.sg_key].id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port_range_min
  port_range_max    = each.value.port_range_max
  remote_ip_prefix  = each.value.remote_group_id == null ? each.value.remote_ip_prefix : null
  remote_group_id   = each.value.remote_group_id
  description       = each.value.description
}
