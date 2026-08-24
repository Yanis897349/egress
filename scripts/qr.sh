#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=./scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command qrencode

VLESS_FILE="${SECRETS_DIR}/vless-reality.txt"
HY2_FILE="${SECRETS_DIR}/hysteria2.txt"
VLESS_PNG="${SECRETS_DIR}/vless-reality.png"
HY2_PNG="${SECRETS_DIR}/hysteria2.png"
readonly PNG_SCALE=10

[[ -s "${VLESS_FILE}" ]] || die "Missing REALITY configuration. Run: make fetch"
[[ -s "${HY2_FILE}" ]] || die "Missing Hysteria2 configuration. Run: make fetch"
[[ ! -L "${SECRETS_DIR}" ]] || die "Refusing to write QR codes through a symbolic-link secrets directory."

PNG_STAGING_DIR="$(mktemp -d "${SECRETS_DIR}/.qr-staging.XXXXXX")"
cleanup() {
  rm -rf -- "${PNG_STAGING_DIR}"
}
trap cleanup EXIT

umask 077
qrencode -t PNG -s "${PNG_SCALE}" -o "${PNG_STAGING_DIR}/vless-reality.png" \
  "$(<"${VLESS_FILE}")"
qrencode -t PNG -s "${PNG_SCALE}" -o "${PNG_STAGING_DIR}/hysteria2.png" \
  "$(<"${HY2_FILE}")"
chmod 0600 \
  "${PNG_STAGING_DIR}/vless-reality.png" \
  "${PNG_STAGING_DIR}/hysteria2.png"
mv "${PNG_STAGING_DIR}/vless-reality.png" "${VLESS_PNG}"
mv "${PNG_STAGING_DIR}/hysteria2.png" "${HY2_PNG}"
rmdir "${PNG_STAGING_DIR}"
trap - EXIT

echo "QR code PNG files saved:"
echo "  ${VLESS_PNG}"
echo "  ${HY2_PNG}"

echo
echo "VLESS + REALITY"
echo
qrencode -t ANSIUTF8 "$(<"${VLESS_FILE}")"

echo
echo "Hysteria2"
echo
qrencode -t ANSIUTF8 "$(<"${HY2_FILE}")"
