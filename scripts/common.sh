#!/usr/bin/env bash

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
  pwd
)"
readonly ROOT_DIR
readonly TERRAFORM_DIR="${ROOT_DIR}/terraform"
readonly SECRETS_DIR="${ROOT_DIR}/secrets"
readonly RUNTIME_DIR="${ROOT_DIR}/.runtime"
readonly KNOWN_HOSTS_FILE="${RUNTIME_DIR}/known_hosts"
export SECRETS_DIR

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/beijing-vps}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-900}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-5}"
SSH_CONNECT_TIMEOUT_SECONDS="${SSH_CONNECT_TIMEOUT_SECONDS:-5}"

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

ensure_ssh_runtime() {
  [[ -f "${SSH_KEY}" ]] || die "SSH private key not found: ${SSH_KEY}"
  install -d -m 0700 "${RUNTIME_DIR}"
  touch "${KNOWN_HOSTS_FILE}"
  chmod 0600 "${KNOWN_HOSTS_FILE}"
}

terraform_output() {
  terraform -chdir="${TERRAFORM_DIR}" output -raw "$1"
}

vpn_ip() {
  terraform_output vpn_ip
}

ssh_options() {
  SSH_OPTIONS=(
    -o BatchMode=yes
    -o "ConnectTimeout=${SSH_CONNECT_TIMEOUT_SECONDS}"
    -o IdentitiesOnly=yes
    -o StrictHostKeyChecking=accept-new
    -o "UserKnownHostsFile=${KNOWN_HOSTS_FILE}"
    -i "${SSH_KEY}"
  )
}

prepare_ssh() {
  require_command ssh
  ensure_ssh_runtime
  ssh_options
}

remote_ssh() {
  local ip=$1
  shift
  # Arguments after the host intentionally form the command interpreted by the
  # remote shell. Callers pass only repository-owned command strings.
  # shellcheck disable=SC2029
  ssh "${SSH_OPTIONS[@]}" "ubuntu@${ip}" "$@"
}

print_remote_diagnostics() {
  local ip=$1

  echo >&2
  echo "== bootstrap log (last 200 lines) ==" >&2
  remote_ssh "${ip}" \
    "sudo tail -n 200 /var/log/beijing-vps-bootstrap.log 2>/dev/null || true" \
    >&2 || true

  echo >&2
  echo "== Xray service ==" >&2
  remote_ssh "${ip}" \
    "sudo systemctl status xray --no-pager 2>/dev/null || true" \
    >&2 || true

  echo >&2
  echo "== sing-box service ==" >&2
  remote_ssh "${ip}" \
    "sudo systemctl status sing-box --no-pager 2>/dev/null || true" \
    >&2 || true
}
