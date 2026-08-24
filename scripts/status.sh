#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=./scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command terraform
prepare_ssh
IP="$(vpn_ip)"

echo "VPS IP: ${IP}"
echo

remote_ssh "${IP}" '
  set -e

  echo "== bootstrap =="
  sudo cat /var/lib/beijing-vps/bootstrap-complete
  echo

  echo "== Xray (VLESS + REALITY) =="
  sudo systemctl is-active xray
  /usr/local/bin/xray version | head -n 1
  sudo /usr/local/bin/xray run -test -config /etc/xray/config.json
  echo

  echo "== sing-box (Hysteria2) =="
  sudo systemctl is-active sing-box
  sing-box version | head -n 1
  sudo sing-box check -c /etc/sing-box/config.json
  echo

  echo "== listeners =="
  sudo ss -lntup | grep ":443" || true
  echo

  echo "== firewall =="
  sudo ufw status
  echo

  echo "== congestion control =="
  sysctl net.ipv4.tcp_congestion_control
'
