#!/usr/bin/env bash
###############################################################################
# scripts/tf.sh — Wrapper for common Terraform operations
# Usage: ./scripts/tf.sh <environment> <command> [extra args]
# Example:
#   ./scripts/tf.sh dev init
#   ./scripts/tf.sh dev plan
#   ./scripts/tf.sh dev apply
#   ./scripts/tf.sh dev destroy
###############################################################################

set -euo pipefail

ENVIRONMENT="${1:-}"
COMMAND="${2:-}"
EXTRA_ARGS="${@:3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_DIR="${REPO_ROOT}/environments/${ENVIRONMENT}"

# ── Validation ────────────────────────────────────────────────────────────
if [[ -z "$ENVIRONMENT" || -z "$COMMAND" ]]; then
  echo "Usage: $0 <environment> <init|plan|apply|destroy|fmt|validate>"
  exit 1
fi

if [[ ! -d "$ENV_DIR" ]]; then
  echo "Error: environment directory not found: $ENV_DIR"
  exit 1
fi

# ── Credential check ──────────────────────────────────────────────────────
required_vars=(HW_ACCESS_KEY HW_SECRET_KEY HW_REGION_NAME HW_DOMAIN_NAME)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: Required environment variable $var is not set."
    exit 1
  fi
done

# OBS backend uses S3-compatible creds
export AWS_ACCESS_KEY_ID="${HW_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${HW_SECRET_KEY}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Environment : ${ENVIRONMENT}"
echo "  Command     : ${COMMAND}"
echo "  Directory   : ${ENV_DIR}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$ENV_DIR"

# ── Check tfvars ──────────────────────────────────────────────────────────
if [[ ! -f "terraform.tfvars" ]]; then
  echo "Warning: terraform.tfvars not found. Copy terraform.tfvars.example and fill in values."
fi

# ── Execute command ───────────────────────────────────────────────────────
case "$COMMAND" in
  init)
    terraform init -upgrade ${EXTRA_ARGS}
    ;;
  validate)
    terraform init -backend=false
    terraform validate
    ;;
  fmt)
    terraform fmt -recursive "${REPO_ROOT}"
    ;;
  plan)
    terraform plan -var-file="terraform.tfvars" -out="${ENVIRONMENT}.tfplan" ${EXTRA_ARGS}
    echo ""
    echo "Plan saved to ${ENVIRONMENT}.tfplan"
    echo "Review the output above, then run: $0 ${ENVIRONMENT} apply"
    ;;
  apply)
    if [[ -f "${ENVIRONMENT}.tfplan" ]]; then
      echo "Applying saved plan file: ${ENVIRONMENT}.tfplan"
      terraform apply "${ENVIRONMENT}.tfplan" ${EXTRA_ARGS}
    else
      echo "No saved plan found. Running plan+apply..."
      terraform apply -var-file="terraform.tfvars" ${EXTRA_ARGS}
    fi
    ;;
  destroy)
    echo ""
    echo "⚠️  WARNING: This will DESTROY all resources in the '${ENVIRONMENT}' environment."
    read -r -p "Type the environment name to confirm: " confirm
    if [[ "$confirm" != "$ENVIRONMENT" ]]; then
      echo "Aborted."
      exit 1
    fi
    terraform destroy -var-file="terraform.tfvars" ${EXTRA_ARGS}
    ;;
  output)
    terraform output ${EXTRA_ARGS}
    ;;
  *)
    echo "Unknown command: $COMMAND"
    echo "Available: init, validate, fmt, plan, apply, destroy, output"
    exit 1
    ;;
esac
