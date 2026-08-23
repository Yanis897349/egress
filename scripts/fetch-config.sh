#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=./scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command terraform
require_command jq
prepare_ssh

IP="$(vpn_ip)"
STAGING_DIR="$(mktemp -d "${ROOT_DIR}/.secrets-staging.XXXXXX")"
BACKUP_DIR=""

cleanup() {
  if [[ -n "${STAGING_DIR:-}" && "${STAGING_DIR}" == "${ROOT_DIR}"/.secrets-staging.* ]]; then
    rm -rf -- "${STAGING_DIR}"
  fi
}
trap cleanup EXIT

chmod 0700 "${STAGING_DIR}"

echo "Retrieving client manifest from ${IP}..."
remote_ssh "${IP}" "sudo cat /root/vpn-client/manifest.json" \
  >"${STAGING_DIR}/manifest.json"
chmod 0600 "${STAGING_DIR}/manifest.json"

"${ROOT_DIR}/scripts/render-config.sh" \
  "${STAGING_DIR}/manifest.json" \
  "${IP}" \
  "${STAGING_DIR}/rendered"

[[ -s "${STAGING_DIR}/rendered/vless-reality.txt" ]]
[[ -s "${STAGING_DIR}/rendered/hysteria2.txt" ]]

if [[ -L "${SECRETS_DIR}" ]]; then
  die "Refusing to replace a symbolic-link secrets directory."
fi

if [[ -e "${SECRETS_DIR}" ]]; then
  BACKUP_DIR="${ROOT_DIR}/.secrets-previous.$$"
  mv "${SECRETS_DIR}" "${BACKUP_DIR}"
fi

if ! mv "${STAGING_DIR}/rendered" "${SECRETS_DIR}"; then
  if [[ -n "${BACKUP_DIR}" && -e "${BACKUP_DIR}" ]]; then
    mv "${BACKUP_DIR}" "${SECRETS_DIR}"
  fi
  die "Could not install the new client configuration."
fi

if [[ -n "${BACKUP_DIR}" && -e "${BACKUP_DIR}" ]]; then
  rm -rf -- "${BACKUP_DIR}"
fi

echo "Client configuration installed atomically:"
echo "  ${SECRETS_DIR}/vless-reality.txt"
echo "  ${SECRETS_DIR}/hysteria2.txt"
