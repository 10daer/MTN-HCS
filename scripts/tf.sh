#!/usr/bin/env bash
###############################################################################
# tf.sh — Terraform wrapper for HCS private cloud deployments
#
# USAGE:
#   ./scripts/tf.sh <environment> <command> [options]
#
# ENVIRONMENTS:
#   dev | staging | prod
#
# COMMANDS:
#   init        Initialize Terraform (download providers, connect to backend)
#   validate    Check syntax and types without calling any API
#   fmt         Auto-format all .tf files in the repo
#   plan        Show what Terraform will create/change/destroy
#   apply       Apply the last saved plan (or plan+apply if no plan exists)
#   destroy     Destroy all resources in the environment (with confirmation)
#   output      Print all outputs from the current state
#   state       Pass-through to terraform state (list, show, rm etc.)
#   refresh     Refresh state from real HCS resources
#   console     Open interactive Terraform console for debugging expressions
#   unlock      Force-unlock the state if a lock is stuck
#   workspace   Show current workspace info
#
# EXAMPLES:
#   ./scripts/tf.sh dev init
#   ./scripts/tf.sh dev plan
#   ./scripts/tf.sh dev apply
#   ./scripts/tf.sh staging plan
#   ./scripts/tf.sh prod apply
#   ./scripts/tf.sh dev output
#   ./scripts/tf.sh dev state list
#   ./scripts/tf.sh dev state show hcs_vpc.this
#   ./scripts/tf.sh dev destroy
#   ./scripts/tf.sh dev console
#   ./scripts/tf.sh dev unlock <lock-id>
#
# PREREQUISITES:
#   1. Export your credentials:
#        export TF_VAR_access_key="<your-ak>"
#        export TF_VAR_secret_key="<your-sk>"
#   2. Copy terraform.tfvars.example to terraform.tfvars in your environment
#   3. Copy backend.tf.example to backend.tf in your environment
#   4. Run init before any other command
#
# CREDENTIAL ENVIRONMENT VARIABLES REQUIRED:
#   TF_VAR_access_key  — HCS Access Key (provider reads this as var.access_key)
#   TF_VAR_secret_key  — HCS Secret Key (provider reads this as var.secret_key)
#
# All other config (region, domain, endpoints) lives in terraform.tfvars.
###############################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Colour codes — makes output readable
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_step()    { echo -e "\n${CYAN}${BOLD}▶ $*${RESET}"; }
log_divider() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

die() {
  log_error "$*"
  exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Parse arguments
# ─────────────────────────────────────────────────────────────────────────────
ENVIRONMENT="${1:-}"
COMMAND="${2:-}"
# All arguments from position 3 onwards are passed through to terraform
shift 2 2>/dev/null || true
PASSTHROUGH_ARGS=("$@")

# ─────────────────────────────────────────────────────────────────────────────
# Resolve paths — works regardless of where you call the script from
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_DIR="${REPO_ROOT}/environments/${ENVIRONMENT}"
PLAN_FILE="${ENV_DIR}/${ENVIRONMENT}.tfplan"

# ─────────────────────────────────────────────────────────────────────────────
# Usage / help
# ─────────────────────────────────────────────────────────────────────────────
show_usage() {
  echo ""
  echo -e "${BOLD}USAGE:${RESET}"
  echo "  ./scripts/tf.sh <environment> <command> [options]"
  echo ""
  echo -e "${BOLD}ENVIRONMENTS:${RESET}"
  echo "  dev | staging | prod"
  echo ""
  echo -e "${BOLD}COMMANDS:${RESET}"
  echo "  init        Download providers, connect to remote state backend"
  echo "  validate    Check syntax — no API calls made"
  echo "  fmt         Auto-format all .tf files"
  echo "  plan        Preview changes — saves plan to <env>.tfplan"
  echo "  apply       Apply the saved plan (or prompt plan+apply)"
  echo "  destroy     Destroy all resources (requires typed confirmation)"
  echo "  output      Show all Terraform outputs"
  echo "  state       Pass-through: state list | show | rm | mv"
  echo "  refresh     Sync state file with real HCS resources"
  echo "  console     Interactive console for testing expressions"
  echo "  unlock      Force-unlock a stuck state lock"
  echo "  workspace   Show workspace info"
  echo ""
  echo -e "${BOLD}EXAMPLES:${RESET}"
  echo "  ./scripts/tf.sh dev init"
  echo "  ./scripts/tf.sh dev plan"
  echo "  ./scripts/tf.sh dev apply"
  echo "  ./scripts/tf.sh dev output"
  echo "  ./scripts/tf.sh dev state list"
  echo "  ./scripts/tf.sh dev state show hcs_vpc.this"
  echo "  ./scripts/tf.sh dev destroy"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Validate inputs
# ─────────────────────────────────────────────────────────────────────────────
validate_inputs() {
  if [[ -z "$ENVIRONMENT" || -z "$COMMAND" ]]; then
    log_error "Missing environment or command."
    show_usage
    exit 1
  fi

  # Check environment directory exists
  if [[ ! -d "$ENV_DIR" ]]; then
    die "Environment directory not found: ${ENV_DIR}
    
    Available environments:"
    ls "${REPO_ROOT}/environments/" 2>/dev/null || echo "  (none found)"
    exit 1
  fi

  # Warn if environment name is unexpected
  case "$ENVIRONMENT" in
    dev|staging|prod) ;;
    *) log_warn "Non-standard environment name: '${ENVIRONMENT}'. Proceeding anyway." ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Check credentials are loaded in the shell
# ─────────────────────────────────────────────────────────────────────────────
check_credentials() {
  log_step "Checking credentials"

  local missing=()
  local required_vars=(
    TF_VAR_access_key
    TF_VAR_secret_key
  )

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo ""
    log_error "The following required environment variables are not set:"
    for var in "${missing[@]}"; do
      echo -e "    ${RED}✗${RESET} $var"
    done
    echo ""
    echo -e "  Export your HCS credentials:"
    echo -e "  ${YELLOW}export TF_VAR_access_key=\"<your-access-key>\"${RESET}"
    echo -e "  ${YELLOW}export TF_VAR_secret_key=\"<your-secret-key>\"${RESET}"
    echo ""
    exit 1
  fi

  # Set OBS backend credentials (S3-compatible — needs AWS_ prefixed vars)
  export AWS_ACCESS_KEY_ID="${TF_VAR_access_key}"
  export AWS_SECRET_ACCESS_KEY="${TF_VAR_secret_key}"

  # Mask the key in output (show first 4 chars only)
  local masked_key="${TF_VAR_access_key:0:4}****"
  log_success "Credentials loaded (AK: ${masked_key})"
}

# ─────────────────────────────────────────────────────────────────────────────
# Check required files exist in the environment
# ─────────────────────────────────────────────────────────────────────────────
check_env_files() {
  log_step "Checking environment files"

  local all_ok=true

  # backend.tf — required for all commands except validate/fmt
  if [[ "$COMMAND" != "validate" && "$COMMAND" != "fmt" ]]; then
    if [[ ! -f "${ENV_DIR}/backend.tf" ]]; then
      log_error "backend.tf not found in ${ENV_DIR}"
      echo ""
      echo "  Create it by copying the template:"
      echo -e "  ${YELLOW}cp ${REPO_ROOT}/backend.tf.example ${ENV_DIR}/backend.tf${RESET}"
      echo "  Then fill in your OBS bucket name, region, and endpoint."
      echo ""
      all_ok=false
    else
      log_success "backend.tf found"
    fi
  fi

  # terraform.tfvars — required for plan/apply/destroy
  if [[ "$COMMAND" == "plan" || "$COMMAND" == "apply" || "$COMMAND" == "destroy" ]]; then
    if [[ ! -f "${ENV_DIR}/terraform.tfvars" ]]; then
      log_error "terraform.tfvars not found in ${ENV_DIR}"
      echo ""
      echo "  Create it by copying the example:"
      echo -e "  ${YELLOW}cp ${ENV_DIR}/terraform.tfvars.example ${ENV_DIR}/terraform.tfvars${RESET}"
      echo "  Then fill in your real values."
      echo ""
      all_ok=false
    else
      log_success "terraform.tfvars found"
    fi
  fi

  # .terraform directory — warn if not initialised
  if [[ "$COMMAND" != "init" && "$COMMAND" != "fmt" && ! -d "${ENV_DIR}/.terraform" ]]; then
    log_warn ".terraform directory not found — you may need to run init first"
    echo -e "  ${YELLOW}./scripts/tf.sh ${ENVIRONMENT} init${RESET}"
  fi

  if [[ "$all_ok" == false ]]; then
    exit 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Print the header banner
# ─────────────────────────────────────────────────────────────────────────────
print_banner() {
  log_divider
  echo -e "  ${BOLD}Terraform HCS Wrapper${RESET}"
  echo -e "  Environment  : ${GREEN}${BOLD}${ENVIRONMENT}${RESET}"
  echo -e "  Command      : ${CYAN}${COMMAND}${RESET}"
  echo -e "  Directory    : ${ENV_DIR}"
  echo -e "  Timestamp    : $(date '+%Y-%m-%d %H:%M:%S %Z')"
  log_divider
}

# ─────────────────────────────────────────────────────────────────────────────
# Production guard — extra confirmation for prod commands
# ─────────────────────────────────────────────────────────────────────────────
prod_guard() {
  if [[ "$ENVIRONMENT" == "prod" ]]; then
    echo ""
    echo -e "${RED}${BOLD}⚠  YOU ARE TARGETING PRODUCTION ⚠${RESET}"
    echo ""
    echo -e "  Command   : ${BOLD}${COMMAND}${RESET}"
    echo -e "  Region    : ${BOLD}from terraform.tfvars${RESET}"
    echo ""
    read -r -p "  Are you sure? Type 'yes-prod' to continue: " confirm
    if [[ "$confirm" != "yes-prod" ]]; then
      log_warn "Aborted by user."
      exit 0
    fi
    echo ""
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────────────────────

cmd_init() {
  log_step "Initializing Terraform"
  echo "  This will:"
  echo "    • Download the HCS provider plugin"
  echo "    • Connect to the OBS remote state backend"
  echo "    • Create .terraform.lock.hcl (commit this file)"
  echo ""

  terraform init -upgrade "${PASSTHROUGH_ARGS[@]}"

  echo ""
  log_success "Initialization complete."
  echo ""
  echo "  Next steps:"
  echo -e "  ${YELLOW}./scripts/tf.sh ${ENVIRONMENT} validate${RESET}   — check syntax"
  echo -e "  ${YELLOW}./scripts/tf.sh ${ENVIRONMENT} plan${RESET}        — preview changes"
}

cmd_validate() {
  log_step "Validating Terraform configuration"
  echo "  Checking syntax and types. No API calls made."
  echo ""

  # Init without backend so validate works without OBS access
  terraform init -backend=false -input=false > /dev/null 2>&1

  terraform validate "${PASSTHROUGH_ARGS[@]}"

  echo ""
  log_success "Validation passed."
}

cmd_fmt() {
  log_step "Formatting all Terraform files"
  echo "  Scanning: ${REPO_ROOT}"
  echo ""

  terraform fmt -recursive "${REPO_ROOT}"

  echo ""
  log_success "Formatting complete."
}

cmd_plan() {
  log_step "Running Terraform plan"
  echo "  Comparing your .tf files against live HCS state."
  echo "  Plan will be saved to: ${PLAN_FILE}"
  echo ""

  terraform plan \
    -var-file="terraform.tfvars" \
    -out="${PLAN_FILE}" \
    "${PASSTHROUGH_ARGS[@]}"

  echo ""
  log_divider
  log_success "Plan saved to: ${PLAN_FILE}"
  echo ""
  echo "  Review the output above carefully:"
  echo "    ${GREEN}+ create${RESET}          — new resource will be created"
  echo "    ${YELLOW}~ update in-place${RESET} — resource will be modified (no downtime)"
  echo "    ${RED}-/+ destroy/recreate${RESET} — resource destroyed then recreated (DOWNTIME)"
  echo "    ${RED}- destroy${RESET}          — resource will be permanently deleted"
  echo ""
  echo "  When ready to apply:"
  echo -e "  ${YELLOW}./scripts/tf.sh ${ENVIRONMENT} apply${RESET}"
  log_divider
}

cmd_apply() {
  if [[ -f "${PLAN_FILE}" ]]; then
    log_step "Applying saved plan"
    echo "  Plan file   : ${PLAN_FILE}"
    echo "  Plan date   : $(date -r "${PLAN_FILE}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || stat -c '%y' "${PLAN_FILE}" 2>/dev/null || echo 'unknown')"
    echo ""
    echo "  This will apply EXACTLY what was shown in the plan."
    echo "  No new decisions will be made."
    echo ""

    terraform apply "${PLAN_FILE}" "${PASSTHROUGH_ARGS[@]}"

    # Clean up plan file after successful apply
    rm -f "${PLAN_FILE}"
    log_success "Plan file removed after successful apply."

  else
    log_warn "No saved plan file found at: ${PLAN_FILE}"
    echo ""
    echo "  It is strongly recommended to run plan first:"
    echo -e "  ${YELLOW}./scripts/tf.sh ${ENVIRONMENT} plan${RESET}"
    echo ""
    read -r -p "  Run plan+apply now without a saved plan? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      log_warn "Aborted. Run plan first."
      exit 0
    fi

    echo ""
    terraform apply \
      -var-file="terraform.tfvars" \
      "${PASSTHROUGH_ARGS[@]}"
  fi

  echo ""
  log_success "Apply complete."
  echo ""
  echo "  View outputs:"
  echo -e "  ${YELLOW}./scripts/tf.sh ${ENVIRONMENT} output${RESET}"
}

cmd_destroy() {
  log_step "Destroy — PERMANENT resource deletion"
  echo ""
  echo -e "  ${RED}${BOLD}WARNING: This will PERMANENTLY DELETE all Terraform-managed"
  echo -e "  resources in the '${ENVIRONMENT}' environment.${RESET}"
  echo ""
  echo "  This includes:"
  echo "    • All ECS instances (servers)"
  echo "    • All VPCs and subnets"
  echo "    • All security groups"
  echo "    • All OBS buckets (and their contents if force_destroy=true)"
  echo "    • All other managed resources"
  echo ""
  echo -e "  ${BOLD}This cannot be undone.${RESET}"
  echo ""
  read -r -p "  Type the environment name '${ENVIRONMENT}' to confirm: " confirm

  if [[ "$confirm" != "$ENVIRONMENT" ]]; then
    log_warn "Confirmation did not match. Aborted."
    exit 0
  fi

  echo ""
  log_warn "Proceeding with destroy in 5 seconds... Press Ctrl+C to abort."
  sleep 5

  terraform destroy \
    -var-file="terraform.tfvars" \
    "${PASSTHROUGH_ARGS[@]}"

  echo ""
  log_success "Destroy complete. All managed resources have been removed."
}

cmd_output() {
  log_step "Terraform outputs"
  echo ""
  terraform output "${PASSTHROUGH_ARGS[@]}"
}

cmd_state() {
  log_step "Terraform state"
  echo ""
  #   ./scripts/tf.sh dev state show hcs_vpc.this
  #   ./scripts/tf.sh dev state rm hcs_vpc.this
  terraform state "${PASSTHROUGH_ARGS[@]}"
}

cmd_refresh() {
  log_step "Refreshing state from live HCS resources"
  echo "  This reads real HCS resource attributes and updates the state file."
  echo "  No resources are created or destroyed."
  echo ""
  terraform refresh \
    -var-file="terraform.tfvars" \
    "${PASSTHROUGH_ARGS[@]}"

  log_success "Refresh complete."
}

cmd_console() {
  log_step "Opening Terraform console"
  echo "  Interactive console for testing expressions against your state."
  echo "  Examples to try:"
  echo "    > var.region"
  echo "    > module.network.vpc_id"
  echo "    > cidrhost(\"10.0.1.0/24\", 5)"
  echo "  Type 'exit' or Ctrl+D to quit."
  echo ""
  terraform console \
    -var-file="terraform.tfvars" \
    "${PASSTHROUGH_ARGS[@]}"
}

cmd_unlock() {
  local lock_id="${PASSTHROUGH_ARGS[0]:-}"
  if [[ -z "$lock_id" ]]; then
    die "Usage: ./scripts/tf.sh ${ENVIRONMENT} unlock <lock-id>
    
    Find the lock ID in the error message from a previous failed terraform command.
    It looks like: 'Lock ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'"
  fi

  log_step "Force-unlocking state"
  log_warn "Only do this if you are CERTAIN no other process is running Terraform."
  echo ""
  read -r -p "  Unlock state with ID '${lock_id}'? [y/N]: " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log_warn "Aborted."
    exit 0
  fi

  terraform force-unlock -force "${lock_id}"
  log_success "State unlocked."
}

cmd_workspace() {
  log_step "Workspace info"
  echo ""
  echo -e "  Current workspace: ${BOLD}$(terraform workspace show)${RESET}"
  echo ""
  echo "  All workspaces:"
  terraform workspace list
}

# ─────────────────────────────────────────────────────────────────────────────
# Main execution
# ─────────────────────────────────────────────────────────────────────────────
main() {
  validate_inputs

  # fmt and validate don't need credentials or env files
  if [[ "$COMMAND" == "fmt" ]]; then
    log_step "Formatting"
    cmd_fmt
    exit 0
  fi

  check_credentials
  check_env_files
  print_banner

  # Extra confirmation for prod on destructive commands
  if [[ "$COMMAND" == "apply" || "$COMMAND" == "destroy" || "$COMMAND" == "refresh" ]]; then
    prod_guard
  fi

  # Change to the environment directory — all terraform commands run from here
  cd "${ENV_DIR}"
  log_info "Working directory: $(pwd)"
  echo ""

  # Dispatch to command handler
  case "$COMMAND" in
    init)       cmd_init ;;
    validate)   cmd_validate ;;
    fmt)        cmd_fmt ;;
    plan)       cmd_plan ;;
    apply)      cmd_apply ;;
    destroy)    cmd_destroy ;;
    output)     cmd_output ;;
    state)      cmd_state ;;
    refresh)    cmd_refresh ;;
    console)    cmd_console ;;
    unlock)     cmd_unlock ;;
    workspace)  cmd_workspace ;;
    *)
      log_error "Unknown command: '${COMMAND}'"
      show_usage
      exit 1
      ;;
  esac
}

main
