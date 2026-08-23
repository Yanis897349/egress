#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
  pwd
)"
readonly ROOT_DIR

TEST_DIR="$(mktemp -d)"
cleanup() {
  rm -rf -- "${TEST_DIR}"
}
trap cleanup EXIT

cat >"${TEST_DIR}/manifest.json" <<'EOF'
{
  "schema_version": 1,
  "reality_sni": "www.microsoft.com",
  "vless_uuid": "123e4567-e89b-12d3-a456-426614174000",
  "reality_public_key": "abcdefghijklmnopqrstuvwxyzABCDEFGH123456789",
  "reality_short_id": "0123456789abcdef",
  "hysteria2_password": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "hysteria2_obfs_password": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "hysteria2_cert_sha256": "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99",
  "sing_box_version": "test"
}
EOF

"${ROOT_DIR}/scripts/render-config.sh" \
  "${TEST_DIR}/manifest.json" \
  "203.0.113.10" \
  "${TEST_DIR}/output"

VLESS_FILE="${TEST_DIR}/output/vless-reality.txt"
HY2_FILE="${TEST_DIR}/output/hysteria2.txt"

grep -q '^vless://123e4567-e89b-12d3-a456-426614174000@203\.0\.113\.10:443?' \
  "${VLESS_FILE}"
grep -q 'security=reality' "${VLESS_FILE}"
grep -q 'pbk=abcdefghijklmnopqrstuvwxyzABCDEFGH123456789' "${VLESS_FILE}"
grep -q 'sid=0123456789abcdef' "${VLESS_FILE}"

grep -q '^hysteria2://a\{48\}@203\.0\.113\.10:443/' "${HY2_FILE}"
grep -q 'insecure=1' "${HY2_FILE}"
grep -q 'obfs=salamander' "${HY2_FILE}"
grep -q 'pinSHA256=AA%3ABB%3ACC' "${HY2_FILE}"

file_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

[[ "$(file_mode "${TEST_DIR}/output")" == "700" ]]
[[ "$(file_mode "${VLESS_FILE}")" == "600" ]]
[[ "$(file_mode "${HY2_FILE}")" == "600" ]]

mkdir "${TEST_DIR}/preserved"
printf 'keep-me\n' >"${TEST_DIR}/preserved/sentinel"
printf '{"schema_version":1}\n' >"${TEST_DIR}/invalid.json"

if "${ROOT_DIR}/scripts/render-config.sh" \
  "${TEST_DIR}/invalid.json" \
  "203.0.113.10" \
  "${TEST_DIR}/preserved" \
  >/dev/null 2>&1; then
  echo "Invalid manifest unexpectedly rendered." >&2
  exit 1
fi

grep -qx 'keep-me' "${TEST_DIR}/preserved/sentinel"

if "${ROOT_DIR}/scripts/render-config.sh" \
  "${TEST_DIR}/manifest.json" \
  "999.0.0.1" \
  "${TEST_DIR}/invalid-ip" \
  >/dev/null 2>&1; then
  echo "Invalid IPv4 address unexpectedly rendered." >&2
  exit 1
fi

echo "render-config tests passed."
