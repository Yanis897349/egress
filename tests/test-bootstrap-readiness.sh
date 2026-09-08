#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "${TEST_DIR}"' EXIT
mkdir -p "${TEST_DIR}/bin"

# Exercise the actual bootstrap trap and readiness block without installing
# packages or touching the host's services, firewall, or credentials.
{
  echo 'set -Eeuo pipefail'
  awk '/^mark_failed\(\)/ { copy = 1 } copy { print } /^trap .* ERR$/ { exit }' \
    "${ROOT_DIR}/cloud-init/setup.sh"
  awk '
    /^echo "Waiting for Xray TCP/ { copy = 1 }
    /^echo "Checking VLESS/ { exit }
    copy { print }
  ' "${ROOT_DIR}/cloud-init/setup.sh"
  echo 'echo readiness-passed'
} >"${TEST_DIR}/check.sh"

cat >"${TEST_DIR}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -eu
if [[ "$1" == status ]]; then
  echo simulated-service-status
elif [[ "${MOCK_SCENARIO}" == inactive ]]; then
  exit 1
fi
EOF

cat >"${TEST_DIR}/bin/sleep" <<'EOF'
#!/usr/bin/env bash
set -eu
attempt=$(cat "${MOCK_DIR}/attempt")
echo "$((attempt + 1))" >"${MOCK_DIR}/attempt"
EOF

cat >"${TEST_DIR}/bin/ss" <<'EOF'
#!/usr/bin/env bash
set -eu
attempt=$(cat "${MOCK_DIR}/attempt")
if [[ "$*" == '-H -lntup' ]]; then
  echo simulated-socket-status
  exit 0
fi
[[ "${MOCK_SCENARIO}" != ss-error ]] || exit 1
port=443
process=xray
if [[ "$*" == '-H -lnup' ]]; then
  process=sing-box
fi
case "${MOCK_SCENARIO}" in
  delayed)
    if [[ "${process}" == xray && "${attempt}" -lt 2 ]] ||
      [[ "${process}" == sing-box && "${attempt}" -lt 4 ]]; then
      exit 0
    fi
    ;;
  missing-tcp) [[ "${process}" != xray ]] || exit 0 ;;
  missing-udp) [[ "${process}" != sing-box ]] || exit 0 ;;
  wrong-port) port=1443 ;;
  wrong-process) process=other ;;
esac
echo "LISTEN 0 4096 0.0.0.0:${port} 0.0.0.0:* users:((\"${process}\",pid=123,fd=3))"
EOF
chmod +x "${TEST_DIR}/bin/"*

for scenario in immediate delayed inactive missing-tcp missing-udp wrong-port wrong-process ss-error; do
  scenario_dir="${TEST_DIR}/${scenario}"
  mkdir -p "${scenario_dir}"
  echo 0 >"${scenario_dir}/attempt"
  result=0
  env "PATH=${TEST_DIR}/bin:${PATH}" "MOCK_SCENARIO=${scenario}" \
    "MOCK_DIR=${scenario_dir}" "FAILED_MARKER=${scenario_dir}/failed" \
    bash "${TEST_DIR}/check.sh" >"${scenario_dir}/output" 2>&1 || result=$?

  case "${scenario}" in
    immediate|delayed)
      [[ "${result}" -eq 0 ]]
      [[ ! -e "${scenario_dir}/failed" ]]
      grep -q '^readiness-passed$' "${scenario_dir}/output"
      expected_attempt=0
      [[ "${scenario}" != delayed ]] || expected_attempt=4
      [[ "$(cat "${scenario_dir}/attempt")" -eq "${expected_attempt}" ]]
      ;;
    *)
      [[ "${result}" -eq 1 ]]
      [[ "$(cat "${scenario_dir}/attempt")" -eq 20 ]]
      grep -q 'Timed out waiting for Xray' "${scenario_dir}/output"
      grep -q 'simulated-service-status' "${scenario_dir}/output"
      grep -q 'simulated-socket-status' "${scenario_dir}/output"
      grep -Eq 'Bootstrap failed with exit code 1 at line [0-9]+ at ' "${scenario_dir}/failed"
      grep -Fq "$(cat "${scenario_dir}/failed")" "${scenario_dir}/output"
      if grep -q '^readiness-passed$' "${scenario_dir}/output"; then
        echo "Bootstrap continued despite ${scenario}." >&2
        exit 1
      fi
      ;;
  esac
done

echo "bootstrap readiness tests passed."
