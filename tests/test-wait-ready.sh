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

mkdir -p "${TEST_DIR}/bin" "${TEST_DIR}/home/.ssh"
touch "${TEST_DIR}/home/.ssh/beijing-vps"
chmod 0600 "${TEST_DIR}/home/.ssh/beijing-vps"

cat >"${TEST_DIR}/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -eu
if [[ "$*" == *"output -raw vpn_ip"* ]]; then
  echo "203.0.113.10"
  exit 0
fi
exit 1
EOF

cat >"${TEST_DIR}/bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -eu
arguments="$*"

if [[ "${arguments}" != *"IdentitiesOnly=yes"* ]]; then
  echo "missing IdentitiesOnly=yes" >&2
  exit 1
fi

if [[ "${arguments}" == *"bootstrap-complete"* ]]; then
  if [[ "${MOCK_BOOTSTRAP_STATE:-failed}" == "failed" ]]; then
    echo "failed"
  else
    echo "pending"
  fi
  exit 0
fi

if [[ "${arguments}" == *"tail -n 200"* ]]; then
  echo "simulated-bootstrap-log"
  exit 0
fi

if [[ "${arguments}" == *"systemctl status"* ]]; then
  echo "simulated-service-status"
  exit 0
fi

exit 0
EOF

chmod +x "${TEST_DIR}/bin/terraform" "${TEST_DIR}/bin/ssh"

COMMON_ENV=(
  env
  "PATH=${TEST_DIR}/bin:${PATH}"
  "HOME=${TEST_DIR}/home"
  "SSH_KEY=${TEST_DIR}/home/.ssh/beijing-vps"
  "POLL_INTERVAL_SECONDS=0.05"
)

if "${COMMON_ENV[@]}" \
  WAIT_TIMEOUT_SECONDS=5 \
  MOCK_BOOTSTRAP_STATE=failed \
  "${ROOT_DIR}/scripts/wait-ready.sh" \
  >"${TEST_DIR}/failed.log" 2>&1; then
  echo "Failed bootstrap unexpectedly reported readiness." >&2
  exit 1
fi

grep -q 'simulated-bootstrap-log' "${TEST_DIR}/failed.log"
grep -q 'Remote bootstrap failed' "${TEST_DIR}/failed.log"

if "${COMMON_ENV[@]}" \
  WAIT_TIMEOUT_SECONDS=1 \
  MOCK_BOOTSTRAP_STATE=pending \
  "${ROOT_DIR}/scripts/wait-ready.sh" \
  >"${TEST_DIR}/timeout.log" 2>&1; then
  echo "Pending bootstrap unexpectedly reported readiness." >&2
  exit 1
fi

grep -q 'simulated-bootstrap-log' "${TEST_DIR}/timeout.log"
grep -q 'Timed out waiting for remote bootstrap' "${TEST_DIR}/timeout.log"

echo "wait-ready tests passed."
