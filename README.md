# Disposable Beijing VPS

Terraform automation for a disposable personal connectivity server on AWS
Lightsail in Tokyo. The server runs:

- VLESS + REALITY on TCP/443
- Hysteria2 + Salamander on UDP/443
- key-only SSH on TCP/22

The central operational command is:

```bash
make rotate
```

It replaces only the Lightsail instance and its firewall rules, waits for the
new bootstrap to complete, retrieves fresh client profiles atomically, checks
the service, and displays new QR codes. No static IP is created.

> Check and comply with applicable law, your university or employer network
> policy, and AWS's acceptable-use policy. Network conditions can change, and
> this project does not guarantee connectivity from any particular network.

## Architecture and security model

Terraform stores infrastructure configuration and the public instance address.
Tunnel credentials are generated on the VPS during bootstrap and do not enter
Terraform configuration or state.

The REALITY private key remains in root-owned server storage and in the
root/sing-box-readable server configuration. A separate root-only client
manifest contains the VLESS UUID, REALITY public key and short ID, Hysteria2
passwords, and certificate fingerprint. The fetch workflow reads that manifest
over key-authenticated SSH, validates it locally, and renders two share links.

Locally retrieved profiles are stored as:

```text
secrets/vless-reality.txt
secrets/hysteria2.txt
```

The directory is mode `0700` and each file is mode `0600`. It, Terraform state,
local tfvars, staging directories, runtime SSH host keys, and private key files
are ignored by Git.

SSH is deliberately reachable from any IPv4 address for recovery while
traveling. Password authentication, keyboard-interactive authentication, and
root login are disabled; only the configured Lightsail key can log in as
`ubuntu`. Restricting TCP/22 to known source CIDRs is a sensible future
hardening step if stable administrator addresses become available.

## Prerequisites

On macOS:

```bash
brew install terraform awscli qrencode shellcheck jq
```

Verify the tools:

```bash
terraform version
aws --version
qrencode --version
shellcheck --version
jq --version
```

Configure AWS credentials using a standard provider-supported source. For a
personal IAM user:

```bash
aws configure
```

Use `ap-northeast-1` as the default region. AWS SSO and the `AWS_PROFILE`
environment variable also work. The identity needs permission to read and
manage Lightsail instances, instance public ports, and the referenced key pair.
Do not put AWS access keys in this repository.

Confirm the active identity:

```bash
aws sts get-caller-identity
```

## SSH key and Lightsail key pair

Create a dedicated local key if needed:

```bash
ssh-keygen -t rsa -b 4096 -a 64 -f ~/.ssh/beijing-vps
chmod 600 ~/.ssh/beijing-vps
ssh-add --apple-use-keychain ~/.ssh/beijing-vps
```

Choose a passphrase when prompted. The final command stores it in the macOS
Keychain and loads the key into `ssh-agent`; the automation uses non-interactive
SSH and therefore cannot prompt for the passphrase itself. Repeat `ssh-add` if
the key is removed from the agent before running an operational command.

In the Lightsail console, select the Tokyo region and upload
`~/.ssh/beijing-vps.pub` as a custom key named `beijing-vps`. Key pairs are
regional. If an existing Lightsail key pair is used instead, set its name in
`terraform.tfvars` and point `SSH_KEY` at the matching private key.

Verify the key is visible:

```bash
aws lightsail get-key-pairs --region ap-northeast-1
```

## Configuration

Inspect currently active Ubuntu blueprints and IPv4 bundles before choosing a
plan:

```bash
aws lightsail get-blueprints \
  --region ap-northeast-1 \
  --query 'blueprints[?isActive && platform==`LINUX_UNIX`].[blueprintId,name]'

aws lightsail get-bundles \
  --region ap-northeast-1 \
  --query 'bundles[].[bundleId,name,price,supportedPlatforms]'
```

Copy the example configuration:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

At minimum, set:

```hcl
bundle_id     = "small_3_0"
key_pair_name = "beijing-vps"
```

The bundle shown is only an example; use an active IPv4-compatible bundle from
the AWS command above. Defaults are:

| Setting | Default |
|---|---|
| Region | `ap-northeast-1` |
| Availability zone | `ap-northeast-1a` |
| Blueprint | `ubuntu_24_04` |
| Instance name | `beijing-vpn` |
| REALITY handshake target | `www.microsoft.com` |

The REALITY target must be a DNS hostname reachable from the VPS that accepts a
TLS 1.3 handshake on port 443. Bootstrap fails visibly if that check fails.

The local private key defaults to `~/.ssh/beijing-vps`. Override it with an
absolute path when necessary:

```bash
export SSH_KEY=/absolute/path/to/private-key
```

## Deploy

Run the local and static checks first:

```bash
make check
```

Initialize and review the proposed infrastructure:

```bash
make init
make plan
```

Deploy:

```bash
make deploy
```

Deployment automatically applies Terraform, waits up to 15 minutes for SSH and
bootstrap, retrieves the profiles, checks the server, and displays QR codes.
Override the timeout when a region is slow:

```bash
WAIT_TIMEOUT_SECONDS=1200 make deploy
```

## Connect client devices

[Hiddify](https://github.com/hiddify/hiddify-app) is the recommended client for
this project. It is open source, supports both of the generated single-profile
links, and is available for iOS, macOS, Android, Windows, and Linux. Install it
only from an official source:

| Device | Official download |
|---|---|
| iPhone or iPad | [Apple App Store](https://apps.apple.com/app/id6596777532) |
| macOS, Windows, or Linux | [Hiddify GitHub releases](https://github.com/hiddify/hiddify-app/releases/latest) |
| Android | [Google Play](https://play.google.com/store/apps/details?id=app.hiddify.com) or [GitHub releases](https://github.com/hiddify/hiddify-app/releases/latest) |

The App Store version also runs on supported Apple-silicon Macs. Store and
download availability varies by region, so install and test the clients before
travel. The Hiddify interface can change between releases; its official
[profile-import tutorial](https://github.com/hiddify/Hiddify-Manager/wiki/Tutorial-for-HiddifyNext-app#adding-a-profile-to-the-app)
uses **Add from clipboard** under the `+` button.

### iPhone or iPad

On the Mac used to deploy the server, display the locally generated QR codes:

```bash
make qr
```

In Hiddify on the phone or tablet:

1. Tap `+`, choose the QR scanner, and allow camera access if prompted.
2. Scan the complete **VLESS + REALITY** QR code shown in Terminal.
3. Repeat for the **Hysteria2** QR code. They are two independent profiles.
4. Select either `Tokyo-REALITY` or `Tokyo-HY2`, tap Connect, and approve the
   iOS VPN configuration when prompted.

Use Hiddify's scanner rather than the standard Camera app. If a QR code does
not fit completely in the Terminal window, enlarge the window or reduce its
font size before scanning.

### macOS

To import without displaying the credential, copy each profile directly to
the clipboard and use `+` -> **Add from clipboard** in Hiddify:

```bash
pbcopy < secrets/vless-reality.txt
```

Import it, then repeat for the second profile:

```bash
pbcopy < secrets/hysteria2.txt
```

Select one of the imported profiles and click Connect. Allow Hiddify to add a
VPN configuration or network extension if macOS requests it.

### Android, Windows, or Linux

The profile contents and QR codes are portable. Install Hiddify on the target
device, then either scan each code produced by `make qr` or securely copy one
file at a time from `secrets/` and use `+` -> **Add from clipboard**. Import
both profiles separately and connect with one at a time.

### Test and maintain the connection

Test both profiles because they use different transports: REALITY uses TCP/443
and Hysteria2 uses UDP/443. A network may permit one and filter the other. With
the client connected, open `https://checkip.amazonaws.com` in a browser; the
displayed address should match `vpn_ip` from:

```bash
make output
```

Every `make rotate` creates new credentials as well as a new endpoint. Remove
the old profiles from each client and import both newly displayed QR codes.

Treat the files, their clipboard contents, and their QR codes as passwords.
Anyone who obtains one can use that profile. Do not commit them, send them over
an untrusted channel, save QR screenshots to cloud storage, or paste them into
an online QR-code generator. `make qr` renders them locally.

## Normal operation

```bash
make output  # Terraform outputs
make status  # bootstrap, sing-box, listeners, UFW, and BBR
make ssh     # SSH to ubuntu@<current-ip>
make fetch   # atomically refresh local profiles
make qr      # display both profile QR codes
make wait    # wait for an in-progress bootstrap
```

The first SSH connection uses trust on first use and records the host key in
`.runtime/known_hosts`. That file is local to this repository and is cleared
after an intentional instance replacement.

## Rotate the endpoint

```bash
make rotate
```

Rotation records the old address, asks Terraform to replace the instance, and
forces the authoritative Lightsail firewall resource to be replaced as well.
The old local profiles remain untouched until the new server is healthy and the
new manifest has rendered successfully. The active files are then replaced and
the old copies are deleted, as selected for this project.

If AWS happens to assign the same IPv4 address, the command still saves the new
working credentials but exits with a warning. Run `make rotate` again if a
different public address is required.

Do not stop and start the instance from the Lightsail console as an IP-rotation
workflow. Terraform state and the local SSH host record may then need a refresh.
Use `make rotate` so the complete lifecycle remains coordinated.

## Destroy and local cleanup

Destroying infrastructure is intentionally interactive:

```bash
make destroy
```

Review Terraform's prompt carefully. Destroying the instance does not delete
the local profiles. Remove them explicitly when no longer needed:

```bash
make clean-secrets
```

Lightsail charges for resources while they exist. Use `make destroy` when the
server is no longer needed and verify the Lightsail console does not contain
unmanaged instances or static IPs.

## Troubleshooting

`wait-ready.sh` distinguishes a remote bootstrap failure from a timeout and
prints the tail of the bootstrap log plus the sing-box service status whenever
SSH is available. To inspect manually:

```bash
make ssh
sudo tail -n 200 /var/log/beijing-vps-bootstrap.log
sudo systemctl status sing-box --no-pager
sudo journalctl -u sing-box --output cat -e
sudo sing-box check -c /etc/sing-box/config.json
```

Common causes of deployment failure:

- the selected bundle or blueprint is inactive;
- the Lightsail key-pair name does not exist in Tokyo;
- the local private key does not match the uploaded public key;
- the REALITY handshake target is unavailable or lacks TLS 1.3;
- AWS credentials lack Lightsail permissions;
- TCP/22 is filtered on the administrator's current network.

If SSH works but a profile does not, run `make status`, test both TCP and UDP
profiles, and try from an independent connection before replacing the endpoint.
Keep a commercial VPN and roaming/eSIM recovery path independent from this VPS.

## Repository layout

```text
.
├── Makefile
├── README.md
├── cloud-init/
│   └── setup.sh
├── scripts/
│   ├── check.sh
│   ├── common.sh
│   ├── fetch-config.sh
│   ├── qr.sh
│   ├── render-config.sh
│   ├── rotate.sh
│   ├── ssh.sh
│   ├── status.sh
│   └── wait-ready.sh
├── terraform/
│   ├── main.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── variables.tf
│   └── versions.tf
└── tests/
    ├── test-render-config.sh
    └── test-wait-ready.sh
```
