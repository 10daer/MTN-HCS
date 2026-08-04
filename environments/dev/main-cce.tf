###############################################################################
# CCE — Kubernetes cluster, node pools, namespaces
# Module: ../../modules/cce            Values: cce.auto.tfvars
#
# Gated on cce_enabled because a CCE cluster is not map-driven: the module
# always creates one cluster, so a flag is the only way to keep this stack
# switched off. Flip cce_enabled = true in cce.auto.tfvars to build it.
#
# Network ids default to the network stack's VPC and first public subnet;
# set cce_vpc_id / cce_subnet_id to pin explicit ids instead. The subnet MUST
# have DNS configured or node registration fails.
###############################################################################

module "cce" {
  count  = var.cce_enabled ? 1 : 0
  source = "../../modules/cce"

  name_prefix = local.name_prefix

  # Cluster
  cluster_flavor_id      = var.cce_cluster_flavor_id
  vpc_id                 = var.cce_vpc_id != "" ? var.cce_vpc_id : module.network.vpc_id
  subnet_id              = var.cce_subnet_id != "" ? var.cce_subnet_id : module.network.public_subnet_id_list[0]
  container_network_type = var.cce_container_network_type
  container_network_cidr = var.cce_container_network_cidr
  service_network_cidr   = var.cce_service_network_cidr
  kube_proxy_mode        = var.cce_kube_proxy_mode
  cluster_eip            = var.cce_cluster_eip
  cluster_multi_az       = var.cce_cluster_multi_az

  # Node pools — the keypair must already exist in HCS
  key_pair_name = var.cce_key_pair_name != "" ? var.cce_key_pair_name : var.key_pair_name
  node_pools    = var.cce_node_pools

  # Kubernetes namespaces
  namespaces = var.cce_namespaces

  tags = local.common_tags

  depends_on = [module.network]
}
