#!/usr/bin/env bash
###############################################################################
# setup-environment.sh — Configure a Terraform environment for first use
#
# This script helps you set up the two files that are gitignored and must
# be created by each person locally:
#   - backend.tf         (where Terraform stores state)
#   - terraform.tfvars   (the real values for your variables)
#
# USAGE:
#   ./scripts/setup-environment.sh <environment>
#
# EXAMPLES:
#   ./scripts/setup-environment.sh dev
#   ./scripts/setup-environment.sh staging
#   ./scripts/setup-environment.sh prod
###############################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Colours
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_step()    { echo -e "\n${CYAN}${BOLD}▶ $*${RESET}"; }
log_divider() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─────────────────────────────────────────────────────────────────────────────
# Validate environment argument
# ─────────────────────────────────────────────────────────────────────────────
ENVIRONMENT="${1:-}"
if [[ -z "$ENVIRONMENT" ]]; then
  log_error "No environment specified."
  echo ""
  echo "Usage: ./scripts/setup-environment.sh <environment>"
  echo "Example: ./scripts/setup-environment.sh dev"
  echo ""
  echo "Available environments:"
  ls "${REPO_ROOT}/environments/" 2>/dev/null | sed 's/^/  /'
  exit 1
fi

ENV_DIR="${REPO_ROOT}/environments/${ENVIRONMENT}"
if [[ ! -d "$ENV_DIR" ]]; then
  log_error "Environment directory not found: ${ENV_DIR}"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Welcome
# ─────────────────────────────────────────────────────────────────────────────
clear
log_divider
echo ""
echo -e "  ${BOLD}Environment Setup: ${GREEN}${ENVIRONMENT}${RESET}"
echo ""
echo "  This will create two files in: ${ENV_DIR}"
echo "  These files are gitignored — they contain real values specific"
echo "  to your deployment and are never committed to the repository."
echo ""
log_divider

# ─────────────────────────────────────────────────────────────────────────────
# Check credentials are loaded first
# ─────────────────────────────────────────────────────────────────────────────
log_step "Checking credentials"
if [[ -z "${TF_VAR_access_key:-}" || -z "${TF_VAR_secret_key:-}" ]]; then
  log_error "Credentials not loaded."
  echo ""
  echo "  Run first:"
  echo -e "  ${YELLOW}source ~/.hcs-credentials.sh${RESET}"
  echo ""
  echo "  If you haven't set up credentials yet:"
  echo -e "  ${YELLOW}./scripts/setup-credentials.sh${RESET}"
  exit 1
fi
log_success "Credentials found (AK: ${TF_VAR_access_key:0:4}****)"

# ─────────────────────────────────────────────────────────────────────────────
# PART 1: backend.tf — choose LOCAL or REMOTE state
# ─────────────────────────────────────────────────────────────────────────────
log_step "Setting up backend.tf (where Terraform stores its state)"
echo ""
echo "  Terraform must store a state file — a record of every resource it"
echo "  manages. You can keep this file in two places:"
echo ""
echo -e "    ${BOLD}1) LOCAL${RESET}   — file on your laptop (environments/${ENVIRONMENT}/terraform.tfstate)"
echo "               Best for: personal testing, sandbox, learning"
echo "               NOT for:  shared environments, prod, CI"
echo ""
echo -e "    ${BOLD}2) REMOTE${RESET}  — file in HCS OBS bucket, shared with the team"
echo "               Best for: dev/staging/prod and any team-shared work"
echo "               Requires: an OBS bucket created beforehand (see docs/00-SETUP.md Step 4)"
echo ""

if [[ "$ENVIRONMENT" == "prod" || "$ENVIRONMENT" == "staging" ]]; then
  default_backend="remote"
  echo -e "  ${YELLOW}Production / staging detected — strongly recommend REMOTE.${RESET}"
else
  default_backend="remote"
fi

BACKEND_FILE="${ENV_DIR}/backend.tf"
SKIP_BACKEND=false

if [[ -f "$BACKEND_FILE" ]]; then
  log_warn "backend.tf already exists."
  read -r -p "  Overwrite it? [y/N]: " overwrite
  if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
    log_info "Keeping existing backend.tf"
    SKIP_BACKEND=true
  fi
fi

if [[ "$SKIP_BACKEND" == false ]]; then
  echo ""
  read -r -p "  Which backend? [local/remote, default=${default_backend}]: " backend_choice
  backend_choice="${backend_choice:-${default_backend}}"
  backend_choice="$(echo "$backend_choice" | tr '[:upper:]' '[:lower:]')"

  case "$backend_choice" in
    local|l)
      log_info "Selected: LOCAL backend"
      if [[ "$ENVIRONMENT" == "prod" || "$ENVIRONMENT" == "staging" ]]; then
        echo ""
        log_warn "You picked LOCAL state for '${ENVIRONMENT}'."
        log_warn "This is almost certainly wrong — local state cannot be shared with the team."
        read -r -p "  Type 'i-know-what-im-doing' to continue: " confirm
        if [[ "$confirm" != "i-know-what-im-doing" ]]; then
          log_warn "Aborted. Re-run and pick 'remote'."
          exit 0
        fi
      fi

      cat > "$BACKEND_FILE" << EOF
###############################################################################
# backend.tf — LOCAL state for ${ENVIRONMENT}
# Generated by: scripts/setup-environment.sh on $(date '+%Y-%m-%d')
# DO NOT COMMIT THIS FILE — it is gitignored.
#
# State is stored in this directory as terraform.tfstate (also gitignored).
# To switch to remote (OBS) state, see: docs/LOCAL-VS-REMOTE-STATE.md
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcs = {
      source  = "huaweicloud/hcs"
      version = "~> 2.4.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF
      log_success "backend.tf created (LOCAL): ${BACKEND_FILE}"
      ;;

    remote|r)
      log_info "Selected: REMOTE backend (HCS OBS)"
      echo ""
      echo "  You need an OBS bucket that already exists. Create one in the HCS"
      echo "  console first if you haven't (see docs/00-SETUP.md Step 4)."
      echo ""
      echo "  Enter the OBS bucket name where Terraform state will be stored."
      echo "  Convention: {project}-{environment}-tfstate"
      echo "  Example:    myapp-dev-tfstate"
      echo ""
      read -r -p "  OBS bucket name: " obs_bucket

      echo ""
      echo "  The state file path within the bucket."
      echo "  Convention: {environment}/terraform.tfstate"
      echo ""
      read -r -p "  State file key [${ENVIRONMENT}/terraform.tfstate]: " obs_key
      obs_key="${obs_key:-${ENVIRONMENT}/terraform.tfstate}"

      echo ""
      read -r -p "  HCS region name [MTN_Cloud]: " obs_region
      obs_region="${obs_region:-MTN_Cloud}"

      echo ""
      echo "  The OBS endpoint URL for your HCS installation."
      echo "  Format:  https://obs.<region>.<hcs-domain>"
      echo "  Example: https://obs.cn-east-3.hcs.your-company.com"
      echo ""
      read -r -p "  OBS endpoint URL: " obs_endpoint

      cat > "$BACKEND_FILE" << EOF
###############################################################################
# backend.tf — REMOTE (OBS) state for ${ENVIRONMENT}
# Generated by: scripts/setup-environment.sh on $(date '+%Y-%m-%d')
# DO NOT COMMIT THIS FILE — it is gitignored.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcs = {
      source  = "huaweicloud/hcs"
      version = "~> 2.4.0"
    }
  }

  backend "s3" {
    # HCS OBS is S3-compatible
    bucket   = "${obs_bucket}"
    key      = "${obs_key}"
    region   = "${obs_region}"
    endpoint = "${obs_endpoint}"

    # Required for non-AWS S3-compatible storage
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    force_path_style            = true

    # Credentials are read from environment variables:
    # AWS_ACCESS_KEY_ID     (set from TF_VAR_access_key by credentials file)
    # AWS_SECRET_ACCESS_KEY (set from TF_VAR_secret_key by credentials file)
  }
}
EOF
      log_success "backend.tf created (REMOTE/OBS): ${BACKEND_FILE}"
      ;;

    *)
      log_error "Unknown choice: '${backend_choice}'. Expected 'local' or 'remote'."
      exit 1
      ;;
  esac
fi

# ─────────────────────────────────────────────────────────────────────────────
# PART 2: terraform.tfvars
# ─────────────────────────────────────────────────────────────────────────────
log_step "Setting up terraform.tfvars (environment variable values)"
echo ""

TFVARS_FILE="${ENV_DIR}/terraform.tfvars"
TFVARS_EXAMPLE="${ENV_DIR}/terraform.tfvars.example"

if [[ -f "$TFVARS_FILE" ]]; then
  log_warn "terraform.tfvars already exists."
  read -r -p "  Overwrite it? [y/N]: " overwrite
  if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
    log_info "Keeping existing terraform.tfvars"
    SKIP_TFVARS=true
  else
    SKIP_TFVARS=false
  fi
else
  SKIP_TFVARS=false
fi

if [[ "$SKIP_TFVARS" == false ]]; then
  if [[ ! -f "$TFVARS_EXAMPLE" ]]; then
    log_error "No terraform.tfvars.example found in ${ENV_DIR}"
    log_error "Cannot generate tfvars. Create it manually."
    exit 1
  fi

  echo "  Fill in values for the ${ENVIRONMENT} environment."
  echo "  Press Enter to accept the default shown in [brackets]."
  echo ""

  # Project metadata
  read -r -p "  Project name (used in resource names): " project_name
  project_name="${project_name:-myapp}"

  read -r -p "  Owner/team name (for tagging): " owner
  owner="${owner:-platform-team}"

  # Use region from credentials
  echo ""
  read -r -p "  HCS region name [MTN_Cloud]: " region_name
  region_name="${region_name:-MTN_Cloud}"

  read -r -p "  HCS domain/tenant name [IT-DEPT]: " domain_name
  domain_name="${domain_name:-IT-DEPT}"

  # HCS specific
  echo ""
  read -r -p "  HCS project name (check HCS console): " hcs_project
  read -r -p "  HCS IAM Auth URL (leave blank if using endpoints) []: " hcs_auth_url
  hcs_auth_url="${hcs_auth_url:-}"

  # Network
  echo ""
  echo "  Network configuration:"
  read -r -p "  VPC CIDR [10.10.0.0/16]: " vpc_cidr
  vpc_cidr="${vpc_cidr:-10.10.0.0/16}"

  read -r -p "  Availability zones (comma-separated) [az1.dc0]: " azs_input
  if [[ -z "$azs_input" ]]; then
    azs_formatted="[\"az1.dc0\"]"
  else
    # Convert "az1,az2" to ["az1", "az2"]
    azs_formatted="[$(echo "$azs_input" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/' )]"
  fi

  read -r -p "  SSH key pair name (must exist in HCS): " key_pair

  read -r -p "  Trusted CIDR for SSH access [10.0.0.0/8]: " ssh_cidr
  ssh_cidr="${ssh_cidr:-10.0.0.0/8}"

  # Compute
  echo ""
  echo "  Compute configuration:"

  local_default_web_count=2
  local_default_app_count=2
  if [[ "$ENVIRONMENT" == "prod" ]]; then
    local_default_web_count=4
    local_default_app_count=4
  fi

  read -r -p "  Web server count [${local_default_web_count}]: " web_count
  web_count="${web_count:-${local_default_web_count}}"

  read -r -p "  App server count [${local_default_app_count}]: " app_count
  app_count="${app_count:-${local_default_app_count}}"

  read -r -p "  Web server flavor [c6.large.2]: " web_flavor
  web_flavor="${web_flavor:-c6.large.2}"

  read -r -p "  App server flavor [c6.xlarge.2]: " app_flavor
  app_flavor="${app_flavor:-c6.xlarge.2}"

  skip_tls_val="false"
  read -r -p "  Skip TLS verification (self-signed certs)? [Y/n]: " skip_tls_input
  if [[ "$skip_tls_input" == "n" || "$skip_tls_input" == "N" ]]; then
    skip_tls_val="false"
  else
    skip_tls_val="true"
  fi

  # Write terraform.tfvars
  cat > "$TFVARS_FILE" << EOF
###############################################################################
# terraform.tfvars — ${ENVIRONMENT} environment values
# Generated by: scripts/setup-environment.sh on $(date '+%Y-%m-%d')
# DO NOT COMMIT THIS FILE — it is gitignored.
###############################################################################

# ── HCS Connection ────────────────────────────────────────────────────────────
hcs_auth_url    = "${hcs_auth_url}"
region          = "${region_name}"
domain_name     = "${domain_name}"
project_name    = "${hcs_project}"
skip_tls_verify = ${skip_tls_val}

# ── Project metadata ──────────────────────────────────────────────────────────
project     = "${project_name}"
environment = "${ENVIRONMENT}"
owner       = "${owner}"

# ── Network ───────────────────────────────────────────────────────────────────
vpc_cidr              = "${vpc_cidr}"
public_subnet_cidrs   = ["$(echo $vpc_cidr | sed 's/0.0\/16/1.0\/24/')","$(echo $vpc_cidr | sed 's/0.0\/16/2.0\/24/')"]
private_subnet_cidrs  = ["$(echo $vpc_cidr | sed 's/0.0\/16/10.0\/24/')","$(echo $vpc_cidr | sed 's/0.0\/16/11.0\/24/')"]
availability_zones    = ${azs_formatted}
dns_servers           = ["100.125.4.25"]
enable_nat_gateway    = true
eip_type              = "5_bgp"
trusted_ssh_cidr      = "${ssh_cidr}"

# ── Compute ───────────────────────────────────────────────────────────────────
key_pair_name      = "${key_pair}"
image_name         = "Ubuntu 22.04 server 64bit"
web_instance_count = ${web_count}
web_flavor_id      = "${web_flavor}"
app_instance_count = ${app_count}
app_flavor_id      = "${app_flavor}"
EOF

  log_success "terraform.tfvars created: ${TFVARS_FILE}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
log_divider
echo ""
echo -e "  ${GREEN}${BOLD}Environment '${ENVIRONMENT}' is ready!${RESET}"
echo ""
echo "  Files created in ${ENV_DIR}:"
[[ -f "${BACKEND_FILE}" ]] && echo -e "    ${GREEN}✓${RESET} backend.tf"
[[ -f "${TFVARS_FILE}"  ]] && echo -e "    ${GREEN}✓${RESET} terraform.tfvars"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo ""
echo -e "  1. Review the files to make sure values look correct:"
echo -e "     ${YELLOW}cat ${ENV_DIR}/backend.tf${RESET}"
echo -e "     ${YELLOW}cat ${ENV_DIR}/terraform.tfvars${RESET}"
echo ""
echo -e "  2. Initialize Terraform:"
echo -e "     ${YELLOW}./scripts/tf.sh ${ENVIRONMENT} init${RESET}"
echo ""
echo -e "  3. Preview what will be created:"
echo -e "     ${YELLOW}./scripts/tf.sh ${ENVIRONMENT} plan${RESET}"
echo ""
echo -e "  4. Deploy:"
echo -e "     ${YELLOW}./scripts/tf.sh ${ENVIRONMENT} apply${RESET}"
echo ""
log_divider
