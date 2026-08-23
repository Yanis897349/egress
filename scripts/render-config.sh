#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: render-config.sh MANIFEST_JSON SERVER_IPV4 OUTPUT_DIR" >&2
  exit 64
fi

readonly MANIFEST_FILE=$1
readonly SERVER_IP=$2
readonly OUTPUT_DIR=$3

command -v jq >/dev/null 2>&1 || {
  echo "Error: Required command not found: jq" >&2
  exit 1
}

[[ -f "${MANIFEST_FILE}" ]] || {
  echo "Error: Manifest not found: ${MANIFEST_FILE}" >&2
  exit 1
}

valid_ipv4() {
  local address=$1
  local octet
  local -a octets

  [[ "${address}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS=. read -r -a octets <<<"${address}"
  [[ ${#octets[@]} -eq 4 ]] || return 1

  for octet in "${octets[@]}"; do
    [[ "${octet}" =~ ^[0-9]{1,3}$ ]] || return 1
    ((10#${octet} <= 255)) || return 1
  done
}

valid_ipv4 "${SERVER_IP}" || {
  echo "Error: Invalid server IPv4 address: ${SERVER_IP}" >&2
  exit 1
}

jq -e '
  .schema_version == 1 and
  (.reality_sni | type == "string" and test("^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}$")) and
  (.vless_uuid | type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")) and
  (.reality_public_key | type == "string" and test("^[A-Za-z0-9_-]{40,64}$")) and
  (.reality_short_id | type == "string" and test("^[0-9a-fA-F]{2,16}$")) and
  (.hysteria2_password | type == "string" and test("^[0-9a-fA-F]{48}$")) and
  (.hysteria2_obfs_password | type == "string" and test("^[0-9a-fA-F]{48}$")) and
  (.hysteria2_cert_sha256 | type == "string" and test("^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$"))
' "${MANIFEST_FILE}" >/dev/null || {
  echo "Error: Client manifest is missing required fields or contains invalid values." >&2
  exit 1
}

REALITY_SNI="$(jq -r '.reality_sni' "${MANIFEST_FILE}")"
VLESS_UUID="$(jq -r '.vless_uuid' "${MANIFEST_FILE}")"
REALITY_PUBLIC_KEY="$(jq -r '.reality_public_key' "${MANIFEST_FILE}")"
REALITY_SHORT_ID="$(jq -r '.reality_short_id' "${MANIFEST_FILE}")"
HY2_PASSWORD="$(jq -r '.hysteria2_password' "${MANIFEST_FILE}")"
HY2_OBFS_PASSWORD="$(jq -r '.hysteria2_obfs_password' "${MANIFEST_FILE}")"
HY2_PIN="$(jq -r '.hysteria2_cert_sha256' "${MANIFEST_FILE}")"

urlencode() {
  jq -nr --arg value "$1" '$value | @uri'
}

VLESS_URI="vless://${VLESS_UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$(urlencode "${REALITY_SNI}")&fp=chrome&pbk=$(urlencode "${REALITY_PUBLIC_KEY}")&sid=$(urlencode "${REALITY_SHORT_ID}")&type=tcp#Tokyo-REALITY"
HY2_URI="hysteria2://${HY2_PASSWORD}@${SERVER_IP}:443/?sni=hy2.local&insecure=1&obfs=salamander&obfs-password=$(urlencode "${HY2_OBFS_PASSWORD}")&pinSHA256=$(urlencode "${HY2_PIN}")#Tokyo-HY2"

umask 077
install -d -m 0700 "${OUTPUT_DIR}"
printf '%s\n' "${VLESS_URI}" >"${OUTPUT_DIR}/vless-reality.txt"
printf '%s\n' "${HY2_URI}" >"${OUTPUT_DIR}/hysteria2.txt"
chmod 0600 \
  "${OUTPUT_DIR}/vless-reality.txt" \
  "${OUTPUT_DIR}/hysteria2.txt"
