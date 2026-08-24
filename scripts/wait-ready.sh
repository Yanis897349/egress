#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=./scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command terraform
prepare_ssh

[[ "${WAIT_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || \
  die "WAIT_TIMEOUT_SECONDS must be a non-negative integer."

IP="$(vpn_ip)"
DEADLINE=$((SECONDS + WAIT_TIMEOUT_SECONDS))

echo "Waiting up to ${WAIT_TIMEOUT_SECONDS}s for SSH on ${IP}..."

while ! remote_ssh "${IP}" true >/dev/null 2>&1; do
  if ((SECONDS >= DEADLINE)); then
    die "Timed out waiting for SSH on ${IP}."
  fi
  sleep "${POLL_INTERVAL_SECONDS}"
done

echo "SSH is available. Waiting for bootstrap..."

while true; do
  BOOTSTRAP_STATE="$(
    remote_ssh "${IP}" '
      if sudo test -f /var/lib/beijing-vps/bootstrap-complete; then
        echo complete
      elif sudo test -f /var/lib/beijing-vps/bootstrap-failed; then
        echo failed
      else
        echo pending
      fi
    ' 2>/dev/null || echo pending
  )"

  case "${BOOTSTRAP_STATE}" in
    complete)
      break
      ;;
    failed)
      print_remote_diagnostics "${IP}"
      die "Remote bootstrap failed."
      ;;
  esac

  if ((SECONDS >= DEADLINE)); then
    print_remote_diagnostics "${IP}"
    die "Timed out waiting for remote bootstrap."
  fi

  sleep "${POLL_INTERVAL_SECONDS}"
done

remote_ssh "${IP}" \
  "sudo systemctl is-active --quiet xray && sudo systemctl is-active --quiet sing-box"
echo "Bootstrap is complete; Xray and sing-box are active."
