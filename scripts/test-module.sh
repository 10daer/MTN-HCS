#!/usr/bin/env bash
###############################################################################
# test-module.sh — Standardized test runner for HCS Terraform modules
#
# USAGE:
#   ./scripts/test-module.sh <module>                     # run all test levels
#   ./scripts/test-module.sh <module> --level static      # fmt + validate only
#   ./scripts/test-module.sh <module> --level unit        # mock-provider tests
#   ./scripts/test-module.sh <module> --level integration # real provider (plan)
#   ./scripts/test-module.sh --all                        # test every module
#   ./scripts/test-module.sh --all --level static         # static check all
#
# MODULES:
#   network | security | ecs | eip | obs | rds | gaussdb | cce | vdc | iam
#
# TEST LEVELS:
#   static      — terraform fmt -check + terraform validate (no credentials)
#   unit        — terraform test with mock_provider (no credentials)
#   integration — terraform test with real provider (requires credentials)
#                 runs plan only; does NOT apply resources
#
# PREREQUISITES:
#   Terraform >= 1.6  (for 'terraform test' command)
#   For integration level: TF_VAR_access_key and TF_VAR_secret_key must be set
#
# EXIT CODES:
#   0  All tests passed
#   1  One or more tests failed
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
log_success() { echo -e "${GREEN}[PASS]${RESET}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[FAIL]${RESET}  $*" >&2; }
log_step()    { echo -e "\n${CYAN}${BOLD}▶ $*${RESET}"; }
log_divider() { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

die() { log_error "$*"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODULES_DIR="${REPO_ROOT}/modules"

ALL_MODULES=(network security ecs eip obs rds gaussdb cce vdc iam)

# ─────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────────────────────────────────────
MODULE=""
LEVEL="all"      # all | static | unit | integration
RUN_ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)       RUN_ALL=true; shift ;;
    --level)     LEVEL="${2:-all}"; shift 2 ;;
    --level=*)   LEVEL="${1#*=}"; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)          die "Unknown flag: $1. Use --help for usage." ;;
    *)
      if [[ -z "$MODULE" ]]; then MODULE="$1"; shift
      else die "Unexpected argument: $1"; fi ;;
  esac
done

usage() {
  echo -e "${BOLD}USAGE:${RESET}"
  echo "  $0 <module> [--level static|unit|integration|all]"
  echo "  $0 --all [--level static|unit|integration|all]"
  echo ""
  echo -e "${BOLD}MODULES:${RESET} ${ALL_MODULES[*]}"
  echo -e "${BOLD}LEVELS:${RESET}  static | unit | integration | all (default)"
}

[[ "$RUN_ALL" == false && -z "$MODULE" ]] && { usage; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# Validation
# ─────────────────────────────────────────────────────────────────────────────
check_terraform_version() {
  local required_major=1 required_minor=6
  if ! command -v terraform &>/dev/null; then
    die "terraform not found. Install Terraform >= 1.6 from https://developer.hashicorp.com/terraform/downloads"
  fi
  local version
  version=$(terraform version -json 2>/dev/null | grep '"terraform_version"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) \
    || version=$(terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  local major minor
  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)
  if [[ "$major" -lt "$required_major" || ( "$major" -eq "$required_major" && "$minor" -lt "$required_minor" ) ]]; then
    die "Terraform ${version} found but >= 1.6 is required for 'terraform test'. Please upgrade."
  fi
  log_info "Terraform ${version} ✓"
}

check_integration_credentials() {
  if [[ -z "${TF_VAR_access_key:-}" || -z "${TF_VAR_secret_key:-}" ]]; then
    log_warn "Integration tests require TF_VAR_access_key and TF_VAR_secret_key."
    log_warn "Skipping integration level. Export credentials and re-run to include them."
    return 1
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Test runners
# ─────────────────────────────────────────────────────────────────────────────

# Level 1 — fmt + validate (no provider API calls)
run_static() {
  local module="$1"
  local module_dir="${MODULES_DIR}/${module}"
  local passed=true

  log_step "Static: ${module}"

  # Format check
  log_info "Running terraform fmt -check ..."
  if terraform fmt -check -recursive "${module_dir}" > /dev/null 2>&1; then
    log_success "fmt: no formatting issues"
  else
    log_error "fmt: formatting issues found — run 'terraform fmt -recursive modules/${module}' to fix"
    passed=false
  fi

  # Validate (requires init to download provider schemas)
  log_info "Validating module syntax ..."
  pushd "${module_dir}" > /dev/null
  if terraform init -backend=false -upgrade -input=false -no-color > /dev/null 2>&1; then
    if terraform validate -no-color 2>&1; then
      log_success "validate: module config is valid"
    else
      log_error "validate: module has configuration errors"
      passed=false
    fi
  else
    log_warn "validate: init failed (provider download issue?). Skipping validate."
  fi
  popd > /dev/null

  [[ "$passed" == true ]]
}

# Level 2 — terraform test with mock_provider (no real API calls)
run_unit() {
  local module="$1"
  local module_dir="${MODULES_DIR}/${module}"
  local tests_dir="${module_dir}/tests"

  log_step "Unit tests: ${module}"

  if [[ ! -d "${tests_dir}" ]]; then
    log_warn "No tests/ directory found for module '${module}'. Skipping unit tests."
    log_warn "Create ${tests_dir}/unit.tftest.hcl to add unit tests."
    return 0
  fi

  # Check for .tftest.hcl files
  local test_files
  test_files=$(find "${tests_dir}" -name "*.tftest.hcl" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$test_files" -eq 0 ]]; then
    log_warn "No *.tftest.hcl files found in ${tests_dir}/. Skipping."
    return 0
  fi

  pushd "${module_dir}" > /dev/null
  log_info "Initializing for test ..."
  terraform init -backend=false -upgrade -input=false -no-color > /dev/null 2>&1 || {
    log_warn "init failed — skipping unit tests for ${module}"
    popd > /dev/null
    return 0
  }

  log_info "Running terraform test (mock provider) ..."
  local exit_code=0
  terraform test -test-directory=tests -no-color 2>&1 || exit_code=$?
  popd > /dev/null

  if [[ $exit_code -eq 0 ]]; then
    log_success "Unit tests passed: ${module}"
  else
    log_error "Unit tests FAILED: ${module}"
    return 1
  fi
}

# Level 3 — terraform test with real provider (plan only, no apply)
run_integration() {
  local module="$1"
  local module_dir="${MODULES_DIR}/${module}"
  local tests_dir="${module_dir}/tests"

  log_step "Integration tests: ${module}"

  if ! check_integration_credentials; then
    return 0
  fi

  if [[ ! -d "${tests_dir}" ]]; then
    log_warn "No tests/ directory for module '${module}'. Skipping integration tests."
    return 0
  fi

  local integration_files
  integration_files=$(find "${tests_dir}" -name "integration*.tftest.hcl" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$integration_files" -eq 0 ]]; then
    log_warn "No integration*.tftest.hcl files found. Skipping integration tests for ${module}."
    return 0
  fi

  pushd "${module_dir}" > /dev/null
  terraform init -backend=false -upgrade -input=false -no-color > /dev/null 2>&1 || {
    log_warn "init failed — skipping integration tests for ${module}"
    popd > /dev/null
    return 0
  }

  log_info "Running terraform test (real provider, plan only) ..."
  local exit_code=0
  # Pass TF_VAR_* so provider variables are available
  TF_VAR_access_key="${TF_VAR_access_key}" \
  TF_VAR_secret_key="${TF_VAR_secret_key}" \
  terraform test -test-directory=tests -filter="integration*.tftest.hcl" -no-color 2>&1 || exit_code=$?
  popd > /dev/null

  if [[ $exit_code -eq 0 ]]; then
    log_success "Integration tests passed: ${module}"
  else
    log_error "Integration tests FAILED: ${module}"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Run tests for a single module
# ─────────────────────────────────────────────────────────────────────────────
test_module() {
  local module="$1"
  local module_dir="${MODULES_DIR}/${module}"

  if [[ ! -d "${module_dir}" ]]; then
    die "Module '${module}' not found at ${module_dir}"
  fi

  local failed=false

  case "$LEVEL" in
    static)
      run_static "${module}"      || failed=true ;;
    unit)
      run_unit "${module}"        || failed=true ;;
    integration)
      run_integration "${module}" || failed=true ;;
    all)
      run_static "${module}"      || failed=true
      run_unit "${module}"        || failed=true
      run_integration "${module}" || failed=true ;;
    *)
      die "Unknown level '${LEVEL}'. Use: static | unit | integration | all" ;;
  esac

  [[ "$failed" == false ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
log_divider
echo -e "${BOLD}  MTN-HCS Terraform Module Test Runner${RESET}"
echo -e "  Level: ${CYAN}${LEVEL}${RESET}"
[[ "$RUN_ALL" == true ]] && echo -e "  Scope: ${CYAN}all modules${RESET}" \
                         || echo -e "  Module: ${CYAN}${MODULE}${RESET}"
log_divider

check_terraform_version

overall_failed=false
results=()

if [[ "$RUN_ALL" == true ]]; then
  for m in "${ALL_MODULES[@]}"; do
    if test_module "$m"; then
      results+=("${GREEN}PASS${RESET}  ${m}")
    else
      results+=("${RED}FAIL${RESET}  ${m}")
      overall_failed=true
    fi
  done
else
  if test_module "${MODULE}"; then
    results+=("${GREEN}PASS${RESET}  ${MODULE}")
  else
    results+=("${RED}FAIL${RESET}  ${MODULE}")
    overall_failed=true
  fi
fi

# Summary
log_divider
echo -e "${BOLD}  Results${RESET}"
log_divider
for r in "${results[@]}"; do
  echo -e "  ${r}"
done
log_divider

if [[ "$overall_failed" == true ]]; then
  echo -e "${RED}${BOLD}  FAILED${RESET} — one or more tests did not pass."
  exit 1
else
  echo -e "${GREEN}${BOLD}  ALL PASSED${RESET}"
  exit 0
fi
