#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
  pwd
)"
readonly ROOT_DIR

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

# Isolate all state, host keys, and follow-up scripts from the real checkout.
mkdir -p "${TEST_DIR}/bin" "${TEST_DIR}/repo/scripts" "${TEST_DIR}/repo/terraform"
cp "${ROOT_DIR}/scripts/rotate.sh" "${ROOT_DIR}/scripts/common.sh" "${TEST_DIR}/repo/scripts/"
for script in wait-ready fetch-config status qr; do
  cat >"${TEST_DIR}/repo/scripts/${script}.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
echo "${0##*/}" >>"${MOCK_LOG}"
EOF
  chmod +x "${TEST_DIR}/repo/scripts/${script}.sh"
done

cat >"${TEST_DIR}/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -eu
shift # -chdir
echo "$*" >>"${MOCK_LOG}"
case "$*" in
  'init -input=false')
    [[ "${MOCK_SCENARIO}" != init-failure ]] || exit 1
    touch "${MOCK_LOG}.initialized"
    ;;
  'state list')
    [[ -f "${MOCK_LOG}.initialized" ]] || exit 1
    [[ "${MOCK_SCENARIO}" != state-failure ]] || exit 1
    if [[ "${MOCK_SCENARIO}" != missing-state ]]; then
      echo aws_lightsail_instance.vpn
    fi
    ;;
  'output -raw vpn_ip')
    [[ "${MOCK_SCENARIO}" != output-failure ]] || exit 1
    [[ "${MOCK_SCENARIO}" != empty-output ]] || exit 0
    if [[ -f "${MOCK_LOG}.applied" ]]; then
      echo 203.0.113.20
    else
      echo 203.0.113.10
    fi
    ;;
  'apply -replace=aws_lightsail_instance.vpn -auto-approve')
    touch "${MOCK_LOG}.applied"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${TEST_DIR}/bin/terraform"

for scenario in init-failure state-failure missing-state output-failure empty-output success; do
  log="${TEST_DIR}/${scenario}.log"
  result=0
  env "PATH=${TEST_DIR}/bin:${PATH}" "MOCK_LOG=${log}" "MOCK_SCENARIO=${scenario}" \
    bash "${TEST_DIR}/repo/scripts/rotate.sh" >"${log}.output" 2>&1 || result=$?

  if [[ "${scenario}" == success ]]; then
    [[ "${result}" -eq 0 ]]
    cat >"${TEST_DIR}/expected.log" <<'EOF'
init -input=false
state list
output -raw vpn_ip
apply -replace=aws_lightsail_instance.vpn -auto-approve
output -raw vpn_ip
wait-ready.sh
fetch-config.sh
status.sh
qr.sh
EOF
    diff -u "${TEST_DIR}/expected.log" "${log}"
  else
    [[ "${result}" -ne 0 ]]
    if grep -q '^apply ' "${log}"; then
      echo "Rotation applied despite ${scenario}." >&2
      exit 1
    fi
  fi
done

grep -q 'restore terraform/terraform.tfstate and terraform/terraform.tfvars' \
  "${TEST_DIR}/missing-state.log.output"
grep -q 'restore terraform/terraform.tfstate and terraform/terraform.tfvars' \
  "${TEST_DIR}/state-failure.log.output"
echo "rotate tests passed."
