###############################################################################
# Provider configuration for the dev environment.
# Credentials MUST be passed via environment variables — never hardcoded.
#
# Required env vars:
#   HW_ACCESS_KEY     - AK for HCS account
#   HW_SECRET_KEY     - SK for HCS account
#   HW_REGION_NAME    - e.g. "cn-north-4"
#   HW_DOMAIN_NAME    - Account/domain name in HCS
#   HW_CLOUD_TYPE     - set to "private" for HCS on-premises
#   HW_AUTH_URL       - IAM endpoint for private HCS (e.g. https://iam.hcs.example.com/v3)
###############################################################################

provider "huaweicloud" {
  # All credentials come from environment variables
  # Explicitly set cloud type for private HCS deployments
  cloud     = "myhuaweicloud.com"         # override for private HCS if needed
  auth_url  = var.hcs_auth_url            # IAM endpoint for private cloud
  region    = var.region
  domain_name = var.domain_name

  # For private HCS, you may need to skip TLS verification if using self-signed certs
  insecure  = var.skip_tls_verify
}
