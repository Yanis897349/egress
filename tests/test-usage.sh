#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
  pwd
)"
readonly ROOT_DIR

TEST_DIR=$(mktemp -d)
cleanup() {
  rm -rf -- "${TEST_DIR}"
}
trap cleanup EXIT

mkdir -p "${TEST_DIR}/repo/scripts" "${TEST_DIR}/bin"
cp "${ROOT_DIR}/scripts/common.sh" "${TEST_DIR}/repo/scripts/common.sh"
cp "${ROOT_DIR}/scripts/usage.sh" "${TEST_DIR}/repo/scripts/usage.sh"

cat >"${TEST_DIR}/bin/aws" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

arguments="$*"
if [[ "${arguments}" == "configure get region" ]]; then
  printf 'ap-northeast-1\n'
elif [[ "${arguments}" == "lightsail get-instances "* ]]; then
  [[ "${arguments}" == *"--region ap-northeast-1"* ]]
  cat <<'JSON'
{
  "instances": [
    {
      "name": "beijing-vpn",
      "bundleId": "micro_3_0",
      "tags": [
        {"key": "Role", "value": "personal-connectivity"},
        {"key": "ManagedBy", "value": "terraform"}
      ]
    }
  ]
}
JSON
elif [[ "${arguments}" == "ce get-cost-and-usage "* ]]; then
  [[ "${arguments}" == *"APN1-TotalDataXfer-In-Bytes"* ]]
  [[ "${arguments}" == *"APN1-TotalDataXfer-Out-Bytes"* ]]
  cat <<'JSON'
{
  "ResultsByTime": [
    {
      "Estimated": true,
      "Groups": [
        {
          "Keys": ["APN1-TotalDataXfer-In-Bytes"],
          "Metrics": {"UsageQuantity": {"Amount": "41.282", "Unit": "GB"}}
        },
        {
          "Keys": ["APN1-TotalDataXfer-Out-Bytes"],
          "Metrics": {"UsageQuantity": {"Amount": "41.137", "Unit": "GB"}}
        }
      ]
    }
  ]
}
JSON
elif [[ "${arguments}" == "lightsail get-bundles "* ]]; then
  [[ "${arguments}" == *"--region ap-northeast-1"* ]]
  [[ "${arguments}" == *"--include-inactive"* ]]
  cat <<'JSON'
{
  "bundles": [
    {"bundleId": "micro_3_0", "transferPerMonthInGb": 2048}
  ]
}
JSON
else
  echo "Unexpected aws arguments: ${arguments}" >&2
  exit 1
fi
EOF

chmod +x "${TEST_DIR}/bin/aws"

PATH="${TEST_DIR}/bin:${PATH}" \
  "${TEST_DIR}/repo/scripts/usage.sh" >"${TEST_DIR}/usage.log"

grep -q '^Instance:  beijing-vpn (ap-northeast-1)$' "${TEST_DIR}/usage.log"
grep -q '^Inbound:   41\.282 GB$' "${TEST_DIR}/usage.log"
grep -q '^Outbound:  41\.137 GB$' "${TEST_DIR}/usage.log"
grep -q '^Total:     82\.419 GB$' "${TEST_DIR}/usage.log"
grep -q '^Plan:      micro_3_0 — 2048 GB/month$' "${TEST_DIR}/usage.log"
grep -q '^Used:      4\.02%$' "${TEST_DIR}/usage.log"
grep -q '^Remaining: 1965\.581 GB$' "${TEST_DIR}/usage.log"
grep -q 'AWS marks the current billing data as estimated' "${TEST_DIR}/usage.log"

echo "usage tests passed."
