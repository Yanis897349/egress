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
readonly SING_BOX_CONFIG_DIR="/etc/sing-box"
readonly SING_BOX_CONFIG_FILE="${SING_BOX_CONFIG_DIR}/config.json"
readonly HY2_KEY="${SING_BOX_CONFIG_DIR}/hysteria2.key"
readonly HY2_CERT="${SING_BOX_CONFIG_DIR}/hysteria2.crt"
readonly XRAY_VERSION="v26.3.27"
readonly XRAY_SHA256="23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae"
readonly XRAY_ARCHIVE="/tmp/Xray-linux-64.zip"
readonly XRAY_BINARY="/usr/local/bin/xray"
readonly XRAY_CONFIG_DIR="/etc/xray"
readonly XRAY_CONFIG_FILE="${XRAY_CONFIG_DIR}/config.json"
readonly REALITY_CHECK_CONFIG="/tmp/reality-client-check.json"
readonly REALITY_CHECK_PORT=19080
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
  unzip \
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

echo "Installing Xray ${XRAY_VERSION}..."
curl -fsSL \
  "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip" \
  -o "${XRAY_ARCHIVE}"
printf '%s  %s\n' "${XRAY_SHA256}" "${XRAY_ARCHIVE}" | sha256sum -c -
unzip -p "${XRAY_ARCHIVE}" xray >"${XRAY_BINARY}.tmp"
chmod 0755 "${XRAY_BINARY}.tmp"
mv "${XRAY_BINARY}.tmp" "${XRAY_BINARY}"
rm -f "${XRAY_ARCHIVE}"
"${XRAY_BINARY}" version

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

if ! id xray >/dev/null 2>&1; then
  useradd \
    --system \
    --user-group \
    --home-dir /var/lib/xray \
    --shell /usr/sbin/nologin \
    xray
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

install -d -m 0750 -o root -g sing-box "${SING_BOX_CONFIG_DIR}"
install -d -m 0750 -o root -g xray "${XRAY_CONFIG_DIR}"

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
  --arg hy2_password "${HY2_PASSWORD}" \
  --arg hy2_obfs_password "${HY2_OBFS_PASSWORD}" \
  '{
    log: {
      level: "info",
      timestamp: true
    },
    inbounds: [
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
            name: "egress",
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
  }' >"${SING_BOX_CONFIG_FILE}.tmp"

chown root:sing-box "${SING_BOX_CONFIG_FILE}.tmp"
chmod 0640 "${SING_BOX_CONFIG_FILE}.tmp"
mv "${SING_BOX_CONFIG_FILE}.tmp" "${SING_BOX_CONFIG_FILE}"

jq -n \
  --arg reality_sni "${REALITY_SNI}" \
  --arg uuid "${UUID}" \
  --arg private_key "${PRIVATE_KEY}" \
  --arg short_id "${SHORT_ID}" \
  '{
    log: {
      loglevel: "warning"
    },
    inbounds: [
      {
        tag: "vless-reality-in",
        listen: "0.0.0.0",
        port: 443,
        protocol: "vless",
        settings: {
          clients: [
            {
              id: $uuid,
              email: "egress",
              flow: "xtls-rprx-vision"
            }
          ],
          decryption: "none"
        },
        streamSettings: {
          network: "tcp",
          security: "reality",
          realitySettings: {
            show: false,
            target: ($reality_sni + ":443"),
            xver: 0,
            serverNames: [$reality_sni],
            privateKey: $private_key,
            minClientVer: "0.0.0",
            maxTimeDiff: 60000,
            shortIds: [$short_id]
          }
        }
      }
    ],
    outbounds: [
      {
        tag: "direct",
        protocol: "freedom"
      }
    ]
  }' >"${XRAY_CONFIG_FILE}.tmp"

chown root:xray "${XRAY_CONFIG_FILE}.tmp"
chmod 0640 "${XRAY_CONFIG_FILE}.tmp"
mv "${XRAY_CONFIG_FILE}.tmp" "${XRAY_CONFIG_FILE}"

cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray VLESS REALITY service
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=xray
Group=xray
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ExecStart=${XRAY_BINARY} run -config ${XRAY_CONFIG_FILE}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

sing-box check -c "${SING_BOX_CONFIG_FILE}"
"${XRAY_BINARY}" run -test -config "${XRAY_CONFIG_FILE}"
systemctl daemon-reload
systemctl enable sing-box
systemctl enable xray
systemctl restart sing-box
systemctl restart xray

for _attempt in {1..20}; do
  if systemctl is-active --quiet sing-box && \
    systemctl is-active --quiet xray; then
    break
  fi
  sleep 1
done

systemctl is-active --quiet sing-box
systemctl is-active --quiet xray
ss -H -lntp | awk '$4 ~ /:443$/ && /xray/ { found = 1 } END { exit !found }'
ss -H -lnup | awk '$4 ~ /:443$/ && /sing-box/ { found = 1 } END { exit !found }'

echo "Checking VLESS + REALITY end to end with a sing-box client..."
jq -n \
  --arg reality_sni "${REALITY_SNI}" \
  --arg server "127.0.0.1" \
  --arg uuid "${UUID}" \
  --arg public_key "${PUBLIC_KEY}" \
  --arg short_id "${SHORT_ID}" \
  --argjson port "${REALITY_CHECK_PORT}" \
  '{
    log: {
      level: "warn"
    },
    inbounds: [
      {
        type: "mixed",
        tag: "reality-check-in",
        listen: "127.0.0.1",
        listen_port: $port
      }
    ],
    outbounds: [
      {
        type: "vless",
        tag: "reality-check-out",
        server: $server,
        server_port: 443,
        uuid: $uuid,
        flow: "xtls-rprx-vision",
        tls: {
          enabled: true,
          server_name: $reality_sni,
          utls: {
            enabled: true,
            fingerprint: "chrome"
          },
          reality: {
            enabled: true,
            public_key: $public_key,
            short_id: $short_id
          }
        }
      }
    ],
    route: {
      final: "reality-check-out"
    }
  }' >"${REALITY_CHECK_CONFIG}"

sing-box check -c "${REALITY_CHECK_CONFIG}"
sing-box run -c "${REALITY_CHECK_CONFIG}" &
REALITY_CHECK_PID=$!
sleep 1

if ! timeout 20 curl -fsS \
  --proxy "socks5h://127.0.0.1:${REALITY_CHECK_PORT}" \
  https://api.ipify.org \
  >/dev/null; then
  kill "${REALITY_CHECK_PID}" >/dev/null 2>&1 || true
  wait "${REALITY_CHECK_PID}" 2>/dev/null || true
  rm -f "${REALITY_CHECK_CONFIG}"
  echo "VLESS + REALITY end-to-end check failed." >&2
  exit 1
fi

kill "${REALITY_CHECK_PID}" >/dev/null 2>&1 || true
wait "${REALITY_CHECK_PID}" 2>/dev/null || true
rm -f "${REALITY_CHECK_CONFIG}"
echo "VLESS + REALITY end-to-end check passed."

HY2_PIN="$(
  openssl x509 \
    -in "${HY2_CERT}" \
    -noout \
    -fingerprint \
    -sha256 |
    sed 's/^.*=//'
)"
SING_BOX_VERSION="$(sing-box version | awk 'NR == 1 { print $3 }')"
XRAY_INSTALLED_VERSION="$("${XRAY_BINARY}" version | awk 'NR == 1 { print $2 }')"

install -d -m 0700 "${CLIENT_DIR}"
jq -n \
  --argjson schema_version 2 \
  --arg reality_sni "${REALITY_SNI}" \
  --arg vless_uuid "${UUID}" \
  --arg reality_public_key "${PUBLIC_KEY}" \
  --arg reality_short_id "${SHORT_ID}" \
  --arg hysteria2_password "${HY2_PASSWORD}" \
  --arg hysteria2_obfs_password "${HY2_OBFS_PASSWORD}" \
  --arg hysteria2_cert_sha256 "${HY2_PIN}" \
  --arg sing_box_version "${SING_BOX_VERSION}" \
  --arg xray_version "${XRAY_INSTALLED_VERSION}" \
  '{
    schema_version: $schema_version,
    reality_sni: $reality_sni,
    vless_uuid: $vless_uuid,
    reality_public_key: $reality_public_key,
    reality_short_id: $reality_short_id,
    hysteria2_password: $hysteria2_password,
    hysteria2_obfs_password: $hysteria2_obfs_password,
    hysteria2_cert_sha256: $hysteria2_cert_sha256,
    sing_box_version: $sing_box_version,
    xray_version: $xray_version
  }' >"${CLIENT_MANIFEST}.tmp"

chmod 0600 "${CLIENT_MANIFEST}.tmp"
mv "${CLIENT_MANIFEST}.tmp" "${CLIENT_MANIFEST}"

trap - ERR
rm -f "${FAILED_MARKER}"
printf 'Bootstrap completed at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >"${COMPLETE_MARKER}"
chmod 0644 "${COMPLETE_MARKER}"

echo "Bootstrap completed successfully."
