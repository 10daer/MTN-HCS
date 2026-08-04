###############################################################################
# ECS — Web tier instances (with self-created EIP)
# Module: ../../modules/ecs            Values: ecs.auto.tfvars
#
# The module address stays `module.web` (not module.ecs) so existing state
# keeps matching — renaming it would force a destroy/create of the instance.
#
# Network ids: by default this reads module.network / module.security outputs
# directly. Set ecs_web_subnet_id / ecs_web_security_group_ids in
# ecs.auto.tfvars to pin explicit ids instead (e.g. to land on a subnet this
# state does not manage).
###############################################################################

module "web" {
  source = "../../modules/ecs"

  name_prefix        = "${local.name_prefix}-web"
  default_image_name = var.image_name
  default_availability_zones = [
    data.hcs_availability_zones.available.names[0]
  ]

  default_security_group_ids = length(var.ecs_web_security_group_ids) > 0 ? var.ecs_web_security_group_ids : [
    module.security.security_group_ids["server"],
    module.network.default_security_group_id,
  ]

  # Use the imported SSH key when one is supplied; otherwise no keypair.
  default_key_pair = var.server_ssh_public_key == "" ? null : "${local.name_prefix}-web-key"
  tags             = local.common_tags

  keypairs = var.server_ssh_public_key == "" ? {} : {
    web = {
      name       = "${local.name_prefix}-web-key"
      public_key = var.server_ssh_public_key
    }
  }

  instances = {
    "web-01" = {
      # Discovered values — never hardcoded (see main.tf)
      flavor_id         = data.hcs_ecs_compute_flavors.web.ids[0]
      image_id          = data.hcs_ims_images.web.images[0].id
      availability_zone = data.hcs_availability_zones.available.names[0]
      subnet_id         = var.ecs_web_subnet_id != "" ? var.ecs_web_subnet_id : module.network.public_subnet_id_list[0]

      system_disk_type = var.web_system_disk_type
      system_disk_size = var.web_system_disk_size

      # Create + associate a fresh EIP through the module.
      assign_eip         = true
      eip_type           = var.eip_type
      eip_bandwidth_size = var.web_eip_bandwidth_size
    }
  }

  depends_on = [module.network, module.security]
}
