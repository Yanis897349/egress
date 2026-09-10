#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

mkdir -p "${TEST_DIR}/bin" "${TEST_DIR}/repo/scripts" "${TEST_DIR}/repo/terraform"
cp "${ROOT_DIR}/scripts/"{common,fetch-config,render-config}.sh "${TEST_DIR}/repo/scripts/"
touch "${TEST_DIR}/key"

cat >"${TEST_DIR}/manifest.json" <<'EOF'
{
  "schema_version": 2,
  "reality_sni": "www.cloudflare.com",
  "vless_uuid": "123e4567-e89b-12d3-a456-426614174000",
  "reality_public_key": "abcdefghijklmnopqrstuvwxyzABCDEFGH123456789",
  "reality_short_id": "0123456789abcdef",
  "hysteria2_password": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "hysteria2_obfs_password": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "hysteria2_cert_sha256": "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99",
  "sing_box_version": "test",
  "xray_version": "test"
}
EOF

cat >"${TEST_DIR}/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -eu
shift # -chdir
case "$*" in
  'output -raw vpn_ip') echo 203.0.113.10 ;;
  'show -json')
    [[ "${MOCK_ZONE}" != failure ]] || exit 1
    jq -n --arg zone "${MOCK_ZONE}" '{values: {root_module: {resources: [
      {address: "aws_lightsail_instance.vpn", values: {availability_zone: $zone}}
    ]}}}'
    ;;
  *) exit 1 ;;
esac
EOF
cat >"${TEST_DIR}/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -eu
cat "${MOCK_MANIFEST}"
EOF
chmod +x "${TEST_DIR}/bin/terraform" "${TEST_DIR}/bin/ssh"

for scenario in 'ap-east-1a Hong%20Kong' 'ap-northeast-1a Tokyo' 'missing invalid' 'failure invalid'; do
  read -r zone label <<<"${scenario}"
  mkdir -p "${TEST_DIR}/repo/secrets"
  printf 'keep-me\n' >"${TEST_DIR}/repo/secrets/sentinel"
  result=0
  # Deliberately conflict with the deployed region to catch accidental use of
  # environment defaults. All Terraform and SSH operations are mocked.
  env "PATH=${TEST_DIR}/bin:${PATH}" "SSH_KEY=${TEST_DIR}/key" \
    "MOCK_MANIFEST=${TEST_DIR}/manifest.json" "MOCK_ZONE=${zone}" \
    AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-west-2 \
    bash "${TEST_DIR}/repo/scripts/fetch-config.sh" >"${TEST_DIR}/fetch.log" 2>&1 || result=$?
  if [[ "${label}" == invalid ]]; then
    [[ "${result}" -ne 0 ]]
    grep -qx 'keep-me' "${TEST_DIR}/repo/secrets/sentinel"
    grep -q 'Cannot read the deployed AWS region' "${TEST_DIR}/fetch.log"
  else
    [[ "${result}" -eq 0 ]]
    [[ ! -e "${TEST_DIR}/repo/secrets/sentinel" ]]
    grep -q "#${label}-REALITY$" "${TEST_DIR}/repo/secrets/vless-reality.txt"
    grep -q "#${label}-HY2$" "${TEST_DIR}/repo/secrets/hysteria2.txt"
  fi
done

echo "fetch-config tests passed."
