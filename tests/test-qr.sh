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

mkdir -p "${TEST_DIR}/repo/scripts" "${TEST_DIR}/repo/secrets" "${TEST_DIR}/bin"
cp "${ROOT_DIR}/scripts/common.sh" "${TEST_DIR}/repo/scripts/common.sh"
cp "${ROOT_DIR}/scripts/qr.sh" "${TEST_DIR}/repo/scripts/qr.sh"

printf 'vless://test-profile\n' >"${TEST_DIR}/repo/secrets/vless-reality.txt"
printf 'hysteria2://test-profile\n' >"${TEST_DIR}/repo/secrets/hysteria2.txt"
chmod 0600 "${TEST_DIR}/repo/secrets/"*.txt

cat >"${TEST_DIR}/bin/qrencode" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

TYPE=""
OUTPUT=""
PAYLOAD=""

while (($# > 0)); do
  case "$1" in
    -t)
      TYPE="$2"
      shift 2
      ;;
    -o)
      OUTPUT="$2"
      shift 2
      ;;
    -s)
      [[ "$2" == "10" ]]
      shift 2
      ;;
    *)
      PAYLOAD="$1"
      shift
      ;;
  esac
done

if [[ "${TYPE}" == "PNG" ]]; then
  printf 'PNG:%s\n' "${PAYLOAD}" >"${OUTPUT}"
else
  printf 'ANSI:%s\n' "${PAYLOAD}"
fi
EOF
chmod +x "${TEST_DIR}/bin/qrencode"

PATH="${TEST_DIR}/bin:${PATH}" \
  "${TEST_DIR}/repo/scripts/qr.sh" >"${TEST_DIR}/qr.log"

grep -q '^PNG:vless://test-profile$' \
  "${TEST_DIR}/repo/secrets/vless-reality.png"
grep -q '^PNG:hysteria2://test-profile$' \
  "${TEST_DIR}/repo/secrets/hysteria2.png"
grep -q '^ANSI:vless://test-profile$' "${TEST_DIR}/qr.log"
grep -q '^ANSI:hysteria2://test-profile$' "${TEST_DIR}/qr.log"
grep -q 'QR code PNG files saved:' "${TEST_DIR}/qr.log"

[[ "$(stat -f '%Lp' "${TEST_DIR}/repo/secrets/vless-reality.png")" == "600" ]]
[[ "$(stat -f '%Lp' "${TEST_DIR}/repo/secrets/hysteria2.png")" == "600" ]]

echo "QR tests passed."
