#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: setup.sh REALITY_SNI" >&2
  exit 64
fi

readonly REALITY_SNI="$1"
readonly STATE_DIR="/var/lib/beijing-vps"
readonly COMPLETE_MARKER="${STATE_DIR}/bootstrap-complete"
readonly FAILED_MARKER="${STATE_DIR}/bootstrap-failed"
readonly SERVER_SECRETS="${STATE_DIR}/server-secrets.json"
readonly CLIENT_DIR="/root/vpn-client"
readonly CLIENT_MANIFEST="${CLIENT_DIR}/manifest.json"
readonly CONFIG_DIR="/etc/sing-box"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly HY2_KEY="${CONFIG_DIR}/hysteria2.key"
readonly HY2_CERT="${CONFIG_DIR}/hysteria2.crt"
readonly LOG_FILE="/var/log/beijing-vps-bootstrap.log"

install -d -m 0755 "${STATE_DIR}"
touch "${LOG_FILE}"
chmod 0600 "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

mark_failed() {
  local exit_code=$?
  trap - ERR
  printf 'Bootstrap failed with exit code %s at %s\n' \
    "${exit_code}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >"${FAILED_MARKER}"
  chmod 0644 "${FAILED_MARKER}"
  exit "${exit_code}"
}
trap mark_failed ERR

if [[ -f "${COMPLETE_MARKER}" ]]; then
  echo "Bootstrap already completed."
  exit 0
fi

rm -f "${FAILED_MARKER}"
umask 077

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  jq \
  openssl \
  ufw

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://sing-box.app/gpg.key \
  -o /etc/apt/keyrings/sagernet.asc
chmod 0644 /etc/apt/keyrings/sagernet.asc

cat >/etc/apt/sources.list.d/sagernet.sources <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF

apt-get update
apt-get install -y sing-box

if [[ -f /usr/lib/sysusers.d/sing-box.conf ]]; then
  systemd-sysusers /usr/lib/sysusers.d/sing-box.conf || true
fi

if ! id sing-box >/dev/null 2>&1; then
  useradd \
    --system \
    --home-dir /var/lib/sing-box \
    --shell /usr/sbin/nologin \
    sing-box
fi

cat >/etc/sysctl.d/99-beijing-vps.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

modprobe tcp_bbr || true
sysctl --system

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

cat >/etc/ssh/sshd_config.d/99-beijing-vps.conf <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
AllowUsers ubuntu
EOF

sshd -t
systemctl reload ssh

echo "Checking REALITY handshake target ${REALITY_SNI}:443..."
timeout 15 openssl s_client \
  -brief \
  -connect "${REALITY_SNI}:443" \
  -servername "${REALITY_SNI}" \
  -tls1_3 \
  </dev/null \
  >/dev/null

if [[ ! -f "${SERVER_SECRETS}" ]]; then
  echo "Generating server credentials..."

  UUID="$(sing-box generate uuid)"
  KEYPAIR="$(sing-box generate reality-keypair)"
  PRIVATE_KEY="$(awk '/PrivateKey/ {print $NF}' <<<"${KEYPAIR}")"
  PUBLIC_KEY="$(awk '/PublicKey/ {print $NF}' <<<"${KEYPAIR}")"
  SHORT_ID="$(sing-box generate rand --hex 8)"
  HY2_PASSWORD="$(openssl rand -hex 24)"
  HY2_OBFS_PASSWORD="$(openssl rand -hex 24)"

  [[ "${UUID}" =~ ^[0-9a-fA-F-]{36}$ ]]
  [[ -n "${PRIVATE_KEY}" ]]
  [[ -n "${PUBLIC_KEY}" ]]
  [[ "${SHORT_ID}" =~ ^[0-9a-fA-F]{16}$ ]]

  jq -n \
    --arg vless_uuid "${UUID}" \
    --arg reality_private_key "${PRIVATE_KEY}" \
    --arg reality_public_key "${PUBLIC_KEY}" \
    --arg reality_short_id "${SHORT_ID}" \
    --arg hysteria2_password "${HY2_PASSWORD}" \
    --arg hysteria2_obfs_password "${HY2_OBFS_PASSWORD}" \
    '{
      vless_uuid: $vless_uuid,
      reality_private_key: $reality_private_key,
      reality_public_key: $reality_public_key,
      reality_short_id: $reality_short_id,
      hysteria2_password: $hysteria2_password,
      hysteria2_obfs_password: $hysteria2_obfs_password
    }' >"${SERVER_SECRETS}.tmp"

  chmod 0600 "${SERVER_SECRETS}.tmp"
  mv "${SERVER_SECRETS}.tmp" "${SERVER_SECRETS}"
fi

jq -e '
  (.vless_uuid | type == "string" and length > 0) and
  (.reality_private_key | type == "string" and length > 0) and
  (.reality_public_key | type == "string" and length > 0) and
  (.reality_short_id | type == "string" and test("^[0-9a-fA-F]{16}$")) and
  (.hysteria2_password | type == "string" and test("^[0-9a-fA-F]{48}$")) and
  (.hysteria2_obfs_password | type == "string" and test("^[0-9a-fA-F]{48}$"))
' "${SERVER_SECRETS}" >/dev/null

UUID="$(jq -r '.vless_uuid' "${SERVER_SECRETS}")"
PRIVATE_KEY="$(jq -r '.reality_private_key' "${SERVER_SECRETS}")"
PUBLIC_KEY="$(jq -r '.reality_public_key' "${SERVER_SECRETS}")"
SHORT_ID="$(jq -r '.reality_short_id' "${SERVER_SECRETS}")"
HY2_PASSWORD="$(jq -r '.hysteria2_password' "${SERVER_SECRETS}")"
HY2_OBFS_PASSWORD="$(jq -r '.hysteria2_obfs_password' "${SERVER_SECRETS}")"

install -d -m 0750 -o root -g sing-box "${CONFIG_DIR}"

if [[ ! -s "${HY2_KEY}" || ! -s "${HY2_CERT}" ]]; then
  echo "Generating Hysteria2 certificate..."
  rm -f "${HY2_KEY}" "${HY2_CERT}"

  openssl genpkey \
    -algorithm EC \
    -pkeyopt ec_paramgen_curve:P-256 \
    -out "${HY2_KEY}"

  openssl req \
    -new \
    -x509 \
    -sha256 \
    -days 3650 \
    -key "${HY2_KEY}" \
    -out "${HY2_CERT}" \
    -subj "/CN=hy2.local" \
    -addext "subjectAltName=DNS:hy2.local"
fi

chown root:sing-box "${HY2_KEY}" "${HY2_CERT}"
chmod 0640 "${HY2_KEY}"
chmod 0644 "${HY2_CERT}"

jq -n \
  --arg reality_sni "${REALITY_SNI}" \
  --arg uuid "${UUID}" \
  --arg private_key "${PRIVATE_KEY}" \
  --arg short_id "${SHORT_ID}" \
  --arg hy2_password "${HY2_PASSWORD}" \
  --arg hy2_obfs_password "${HY2_OBFS_PASSWORD}" \
  '{
    log: {
      level: "info",
      timestamp: true
    },
    inbounds: [
      {
        type: "vless",
        tag: "vless-reality-in",
        listen: "0.0.0.0",
        listen_port: 443,
        users: [
          {
            name: "exchange",
            uuid: $uuid,
            flow: "xtls-rprx-vision"
          }
        ],
        tls: {
          enabled: true,
          server_name: $reality_sni,
          reality: {
            enabled: true,
            handshake: {
              server: $reality_sni,
              server_port: 443
            },
            private_key: $private_key,
            short_id: [$short_id],
            max_time_difference: "1m"
          }
        }
      },
      {
        type: "hysteria2",
        tag: "hy2-in",
        listen: "0.0.0.0",
        listen_port: 443,
        obfs: {
          type: "salamander",
          password: $hy2_obfs_password
        },
        users: [
          {
            name: "exchange",
            password: $hy2_password
          }
        ],
        tls: {
          enabled: true,
          server_name: "hy2.local",
          certificate_path: "/etc/sing-box/hysteria2.crt",
          key_path: "/etc/sing-box/hysteria2.key"
        }
      }
    ],
    outbounds: [
      {
        type: "direct",
        tag: "direct"
      }
    ],
    route: {
      final: "direct"
    }
  }' >"${CONFIG_FILE}.tmp"

chown root:sing-box "${CONFIG_FILE}.tmp"
chmod 0640 "${CONFIG_FILE}.tmp"
mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"

sing-box check -c "${CONFIG_FILE}"
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

for _attempt in {1..20}; do
  if systemctl is-active --quiet sing-box; then
    break
  fi
  sleep 1
done

systemctl is-active --quiet sing-box
ss -H -lnt | awk '$4 ~ /:443$/ { found = 1 } END { exit !found }'
ss -H -lnu | awk '$4 ~ /:443$/ { found = 1 } END { exit !found }'

HY2_PIN="$(
  openssl x509 \
    -in "${HY2_CERT}" \
    -noout \
    -fingerprint \
    -sha256 |
    sed 's/^.*=//'
)"
SING_BOX_VERSION="$(sing-box version | awk 'NR == 1 { print $3 }')"

install -d -m 0700 "${CLIENT_DIR}"
jq -n \
  --argjson schema_version 1 \
  --arg reality_sni "${REALITY_SNI}" \
  --arg vless_uuid "${UUID}" \
  --arg reality_public_key "${PUBLIC_KEY}" \
  --arg reality_short_id "${SHORT_ID}" \
  --arg hysteria2_password "${HY2_PASSWORD}" \
  --arg hysteria2_obfs_password "${HY2_OBFS_PASSWORD}" \
  --arg hysteria2_cert_sha256 "${HY2_PIN}" \
  --arg sing_box_version "${SING_BOX_VERSION}" \
  '{
    schema_version: $schema_version,
    reality_sni: $reality_sni,
    vless_uuid: $vless_uuid,
    reality_public_key: $reality_public_key,
    reality_short_id: $reality_short_id,
    hysteria2_password: $hysteria2_password,
    hysteria2_obfs_password: $hysteria2_obfs_password,
    hysteria2_cert_sha256: $hysteria2_cert_sha256,
    sing_box_version: $sing_box_version
  }' >"${CLIENT_MANIFEST}.tmp"

chmod 0600 "${CLIENT_MANIFEST}.tmp"
mv "${CLIENT_MANIFEST}.tmp" "${CLIENT_MANIFEST}"

trap - ERR
rm -f "${FAILED_MARKER}"
printf 'Bootstrap completed at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >"${COMPLETE_MARKER}"
chmod 0644 "${COMPLETE_MARKER}"

echo "Bootstrap completed successfully."
