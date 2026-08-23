#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=./scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command terraform
prepare_ssh
IP="$(vpn_ip)"

exec ssh "${SSH_OPTIONS[@]}" "ubuntu@${IP}" "$@"
