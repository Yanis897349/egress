#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=./scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command terraform
require_command shellcheck
require_command jq
require_command make

SHELL_FILES=()
while IFS= read -r shell_file; do
  SHELL_FILES+=("${shell_file}")
done < <(
  find "${ROOT_DIR}/cloud-init" "${ROOT_DIR}/scripts" "${ROOT_DIR}/tests" \
    -type f -name '*.sh' -print | sort
)

echo "Checking Bash syntax..."
bash -n "${SHELL_FILES[@]}"

echo "Running ShellCheck..."
shellcheck -x "${SHELL_FILES[@]}"

echo "Checking Terraform formatting..."
terraform -chdir="${TERRAFORM_DIR}" fmt -check

echo "Initializing Terraform without a backend..."
terraform -chdir="${TERRAFORM_DIR}" init -backend=false -input=false

echo "Validating Terraform..."
terraform -chdir="${TERRAFORM_DIR}" validate

echo "Testing client URI rendering..."
"${ROOT_DIR}/tests/test-render-config.sh"

echo "Testing readiness failure and timeout handling..."
"${ROOT_DIR}/tests/test-wait-ready.sh"

echo "Testing QR display and PNG generation..."
"${ROOT_DIR}/tests/test-qr.sh"

echo "Dry-running operator workflows..."
make -C "${ROOT_DIR}" -n deploy >/dev/null
make -C "${ROOT_DIR}" -n rotate >/dev/null
make -C "${ROOT_DIR}" -n destroy >/dev/null

echo "All checks passed."
