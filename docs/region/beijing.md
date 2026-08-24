# Beijing deployment via AWS Tokyo

This guide configures Egress for use from Beijing with an AWS Lightsail
instance in Tokyo (`ap-northeast-1`). Tokyo is the checked-in deployment
profile, not a guarantee of connectivity or performance from every Beijing
network.

Read the repository's [architecture, security model, and general
workflow](../../README.md) before deploying.

## AWS authentication

Configure AWS credentials using a provider-supported source. For a personal
IAM user:

```bash
aws configure
```

Use `ap-northeast-1` as the default region. AWS SSO and `AWS_PROFILE` also work.
The identity needs permission to read and manage Lightsail instances, instance
public ports, and the referenced key pair.

Confirm the active identity:

```bash
aws sts get-caller-identity
```

## SSH key and Lightsail key pair

Create the dedicated local key if needed:

```bash
ssh-keygen -t rsa -b 4096 -a 64 -f ~/.ssh/beijing-vps
chmod 600 ~/.ssh/beijing-vps
ssh-add --apple-use-keychain ~/.ssh/beijing-vps
```

Choose a passphrase when prompted. The final command stores it in the macOS
Keychain and loads the key into `ssh-agent`; the automation uses non-interactive
SSH and cannot prompt for the passphrase. Repeat `ssh-add` if the key is removed
from the agent before running an operational command.

In the Lightsail console, select the Tokyo region and upload
`~/.ssh/beijing-vps.pub` as a custom key named `beijing-vps`. Key pairs are
regional. If an existing Lightsail key pair is used instead, set its name in
`terraform.tfvars` and point `SSH_KEY` at the matching private key.

Verify the key is visible:

```bash
aws lightsail get-key-pairs --region ap-northeast-1
```

## Check the Tokyo image and plan

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

Confirm the intended availability zone is listed:

```bash
aws lightsail get-regions \
  --include-availability-zones \
  --query 'regions[?name==`ap-northeast-1`].availabilityZones[].zoneName'
```

The example uses the `ubuntu_24_04` blueprint, `micro_3_0` bundle, and
`ap-northeast-1a` availability zone. Replace any value that is not currently
active or available.

## Configure the Beijing deployment

Copy the example:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Use these values:

```hcl
aws_region        = "ap-northeast-1"
availability_zone = "ap-northeast-1a"
instance_name     = "beijing-vpn"
blueprint_id      = "ubuntu_24_04"
bundle_id         = "micro_3_0"
key_pair_name     = "beijing-vps"
reality_sni       = "www.cloudflare.com"
```

The region, availability zone, instance name, blueprint, and REALITY target
already match the Terraform defaults. They are shown explicitly here so the
regional profile is easy to review. `bundle_id` and `key_pair_name` are
required.

The tested REALITY target is `www.cloudflare.com`. Bootstrap checks both its
direct TLS 1.3 handshake and an end-to-end request through the REALITY proxy.
Do not change it casually: a normal TLS handshake can succeed even when the
target's certificate flight is unsuitable for REALITY.

The local private key defaults to `~/.ssh/beijing-vps`. Override it when using
a different key:

```bash
export SSH_KEY=/absolute/path/to/private-key
```

## Deploy

Run the checks, initialize Terraform, and review the plan:

```bash
make check
make init
make plan
```

The plan should create one Lightsail instance in Tokyo and public-port rules
for TCP/22, TCP/443, and UDP/443. It should not create a static IP, database,
or load balancer.

Deploy after reviewing the plan:

```bash
make deploy
```

This creates a chargeable server, waits for bootstrap, retrieves both client
profiles, checks the services, and displays QR codes. Allow up to 15 minutes;
for a slower deployment, use:

```bash
WAIT_TIMEOUT_SECONDS=1200 make deploy
```

## Connect client devices

[Hiddify](https://github.com/hiddify/hiddify-app) is the tested client for this
profile. It supports both generated single-profile links and is available for
iOS, macOS, Android, Windows, and Linux. Install it only from an official
source:

| Device | Official download |
|---|---|
| iPhone or iPad | [Apple App Store](https://apps.apple.com/app/id6596777532) |
| macOS, Windows, or Linux | [Hiddify GitHub releases](https://github.com/hiddify/hiddify-app/releases/latest) |
| Android | [Google Play](https://play.google.com/store/apps/details?id=app.hiddify.com) or [GitHub releases](https://github.com/hiddify/hiddify-app/releases/latest) |

Download availability varies by region, so install and test the clients before
travel. The interface can change between releases; Hiddify's
[profile-import tutorial](https://github.com/hiddify/Hiddify-Manager/wiki/Tutorial-for-HiddifyNext-app#adding-a-profile-to-the-app)
uses **Add from clipboard** under the `+` button.

### iPhone or iPad

On the Mac used for deployment, display the QR codes and save PNG copies under
`secrets/`:

```bash
make qr
```

In Hiddify:

1. Tap `+`, choose the QR scanner, and allow camera access if prompted.
2. Scan the complete **VLESS + REALITY** QR code shown in Terminal.
3. Repeat for **Hysteria2**; the two codes are independent profiles.
4. Select `Tokyo-REALITY` or `Tokyo-HY2`, tap Connect, and approve the iOS VPN
   configuration when prompted.

Use Hiddify's scanner rather than the standard Camera app. If a QR code does
not fit in the Terminal window, enlarge the window or reduce its font size. You
can instead open `secrets/vless-reality.png` and `secrets/hysteria2.png` in
Preview and scan the larger image.

### macOS

Copy each profile directly to the clipboard and use `+` -> **Add from
clipboard** in Hiddify:

```bash
pbcopy < secrets/vless-reality.txt
```

Import it, then repeat for the second profile:

```bash
pbcopy < secrets/hysteria2.txt
```

Select one imported profile and click Connect. Allow Hiddify to add a VPN
configuration or network extension if macOS requests it.

### Android, Windows, or Linux

Install Hiddify on the target device, then scan each code produced by `make qr`
or securely copy one file at a time from `secrets/` and use `+` -> **Add from
clipboard**. Import the profiles separately and connect with one at a time.

### Test the Beijing connection

Test both profiles because they use different transports. A network may permit
one and filter the other. With the client connected, open
`https://checkip.amazonaws.com`; the displayed address should match `vpn_ip`
from:

```bash
make output
```

Every `make rotate` creates a new Tokyo endpoint and new credentials. Remove
the old `Tokyo-REALITY` and `Tokyo-HY2` profiles from each client and import
both newly generated profiles.

Treat the profile files and QR codes like passwords. Do not commit them, copy
them through an untrusted channel, save QR screenshots to cloud storage, or
paste them into an online QR generator.

## Beijing deployment troubleshooting

The bootstrap log for this profile is
`/var/log/beijing-vps-bootstrap.log`. The readiness workflow prints its tail
and both service statuses when SSH is available. To inspect manually:

```bash
make ssh
sudo tail -n 200 /var/log/beijing-vps-bootstrap.log
sudo systemctl status xray sing-box --no-pager
sudo journalctl -u xray --output cat -e
sudo journalctl -u sing-box --output cat -e
sudo /usr/local/bin/xray run -test -config /etc/xray/config.json
sudo sing-box check -c /etc/sing-box/config.json
```

Region-specific failure causes include a Lightsail key named `beijing-vps`
that is missing from Tokyo, a local `~/.ssh/beijing-vps` key that does not match
the uploaded public key, or an unavailable blueprint or bundle in
`ap-northeast-1`.

If SSH works but a profile does not, run `make status`, test both TCP and UDP
profiles, and try from an independent connection before rotating. Keep a
commercial VPN and roaming/eSIM recovery path independent from this VPS.

When the server is no longer needed, run `make destroy`, then verify in the
Tokyo Lightsail console that no instance remains. Run `make clean-secrets` to
remove the local profiles and QR images.
