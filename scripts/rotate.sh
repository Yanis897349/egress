#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=./scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command terraform
OLD_IP="$(vpn_ip)"

echo "Replacing the Lightsail instance at ${OLD_IP}..."
terraform -chdir="${TERRAFORM_DIR}" apply \
  -replace=aws_lightsail_instance.vpn \
  -auto-approve

NEW_IP="$(vpn_ip)"

# The host key belongs to the destroyed VM. This file is workspace-local and
# contains no entries for unrelated hosts.
install -d -m 0700 "${RUNTIME_DIR}"
: >"${KNOWN_HOSTS_FILE}"
chmod 0600 "${KNOWN_HOSTS_FILE}"

"${ROOT_DIR}/scripts/wait-ready.sh"
"${ROOT_DIR}/scripts/fetch-config.sh"
"${ROOT_DIR}/scripts/status.sh"
"${ROOT_DIR}/scripts/qr.sh"

if [[ "${NEW_IP}" == "${OLD_IP}" ]]; then
  echo >&2
  echo "Warning: AWS reassigned the same public IPv4 address (${NEW_IP})." >&2
  echo "The replacement is healthy and its new credentials were saved, but" >&2
  echo "run 'make rotate' again if a different endpoint address is required." >&2
  exit 2
fi

echo "Rotation complete: ${OLD_IP} -> ${NEW_IP}"
