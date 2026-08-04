###############################################################################
# OBS — buckets, ACLs, objects, bucket policies
# Module: ../../modules/obs            Values: obs.auto.tfvars
#
# Inert until obs.auto.tfvars defines buckets: every input defaults to {}.
#
# Bucket names are globally unique per HCS deployment. A bucket entry with no
# `bucket` field is named "{name_prefix}-{key}", i.e.
# "lagos-mtn-1_A_and_E-dev-<key>" — note OBS names must be DNS-compliant
# (lowercase, no underscores), so for this project set `bucket` explicitly.
###############################################################################

module "obs" {
  source = "../../modules/obs"

  name_prefix = local.name_prefix
  tags        = local.common_tags

  buckets         = var.obs_buckets
  bucket_acls     = var.obs_bucket_acls
  objects         = var.obs_objects
  object_acls     = var.obs_object_acls
  bucket_policies = var.obs_bucket_policies

  existing_buckets = var.obs_existing_buckets
}
