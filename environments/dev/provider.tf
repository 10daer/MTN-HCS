###############################################################################
# Provider configuration for the dev environment.
# 
# Credentials:
#   Set via environment variables (preferred) or directly in terraform.tfvars.
#   export TF_VAR_access_key="<your-ak>"
#   export TF_VAR_secret_key="<your-sk>"
#
# Endpoints:
#   Custom HCS service endpoints are set via the `endpoints` variable
#   in terraform.tfvars — one map(string) covering all services.
###############################################################################

provider "hcs" {
  region       = var.region
  domain_name  = var.domain_name
  project_name = var.project_name
  access_key   = var.access_key
  secret_key   = var.secret_key
  auth_url     = var.hcs_auth_url
  insecure     = var.skip_tls_verify

  # Custom service endpoint overrides — populated per-environment in terraform.tfvars
  endpoints = var.endpoints
}