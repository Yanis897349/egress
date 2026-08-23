#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=./scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command qrencode

VLESS_FILE="${SECRETS_DIR}/vless-reality.txt"
HY2_FILE="${SECRETS_DIR}/hysteria2.txt"

[[ -s "${VLESS_FILE}" ]] || die "Missing REALITY configuration. Run: make fetch"
[[ -s "${HY2_FILE}" ]] || die "Missing Hysteria2 configuration. Run: make fetch"

echo
echo "VLESS + REALITY"
echo
qrencode -t ANSIUTF8 <"${VLESS_FILE}"

echo
echo "Hysteria2"
echo
qrencode -t ANSIUTF8 <"${HY2_FILE}"
