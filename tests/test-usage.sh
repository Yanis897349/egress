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
  printf '%s\n' "${MOCK_CONFIG_REGION}"
elif [[ "${arguments}" == "lightsail get-instances "* ]]; then
  [[ "${arguments}" == *"--region ${MOCK_REGION}"* ]]
  cat <<JSON
{
  "instances": [
    {
      "name": "${MOCK_INSTANCE}",
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
  [[ "${arguments}" == *"${MOCK_BILLING_CODE}-TotalDataXfer-In-Bytes"* ]]
  [[ "${arguments}" == *"${MOCK_BILLING_CODE}-TotalDataXfer-Out-Bytes"* ]]
  cat <<JSON
{
  "ResultsByTime": [
    {
      "Estimated": true,
      "Groups": [
        {
          "Keys": ["${MOCK_BILLING_CODE}-TotalDataXfer-In-Bytes"],
          "Metrics": {"UsageQuantity": {"Amount": "41.282", "Unit": "GB"}}
        },
        {
          "Keys": ["${MOCK_BILLING_CODE}-TotalDataXfer-Out-Bytes"],
          "Metrics": {"UsageQuantity": {"Amount": "41.137", "Unit": "GB"}}
        }
      ]
    }
  ]
}
JSON
elif [[ "${arguments}" == "lightsail get-bundles "* ]]; then
  [[ "${arguments}" == *"--region ${MOCK_REGION}"* ]]
  [[ "${arguments}" == *"--include-inactive"* ]]
  cat <<JSON
{
  "bundles": [
    {"bundleId": "micro_3_0", "transferPerMonthInGb": ${MOCK_ALLOWANCE}}
  ]
}
JSON
else
  echo "Unexpected aws arguments: ${arguments}" >&2
  exit 1
fi
EOF

chmod +x "${TEST_DIR}/bin/aws"

for scenario in configured-tokyo default-hong-kong explicit-hong-kong; do
  config_region=""
  region_override=""
  expected_region=ap-east-1
  billing_code=APE1
  instance=hongkong-vpn
  allowance=1024
  used=8.05
  remaining=941.581
  case "${scenario}" in
    configured-tokyo)
      config_region=ap-northeast-1
      expected_region=ap-northeast-1
      billing_code=APN1
      instance=beijing-vpn
      allowance=2048
      used=4.02
      remaining=1965.581
      ;;
    explicit-hong-kong)
      config_region=ap-northeast-1
      region_override=ap-east-1
      ;;
  esac

  env -u LIGHTSAIL_BILLING_REGION_CODE -u LIGHTSAIL_INSTANCE_NAME \
    "PATH=${TEST_DIR}/bin:${PATH}" "AWS_REGION=${region_override}" AWS_DEFAULT_REGION= \
    "MOCK_CONFIG_REGION=${config_region}" "MOCK_REGION=${expected_region}" \
    "MOCK_BILLING_CODE=${billing_code}" "MOCK_INSTANCE=${instance}" \
    "MOCK_ALLOWANCE=${allowance}" \
    "${TEST_DIR}/repo/scripts/usage.sh" >"${TEST_DIR}/usage.log"

  grep -Fxq "Instance:  ${instance} (${expected_region})" "${TEST_DIR}/usage.log"
  grep -q '^Inbound:   41\.282 GB$' "${TEST_DIR}/usage.log"
  grep -q '^Outbound:  41\.137 GB$' "${TEST_DIR}/usage.log"
  grep -q '^Total:     82\.419 GB$' "${TEST_DIR}/usage.log"
  grep -Fxq "Plan:      micro_3_0 — ${allowance} GB/month" "${TEST_DIR}/usage.log"
  grep -Fxq "Used:      ${used}%" "${TEST_DIR}/usage.log"
  grep -Fxq "Remaining: ${remaining} GB" "${TEST_DIR}/usage.log"
  grep -q 'AWS marks the current billing data as estimated' "${TEST_DIR}/usage.log"
done

echo "usage tests passed."
