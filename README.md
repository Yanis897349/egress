# Egress

[![CI](https://github.com/Yanis897349/egress/actions/workflows/ci.yml/badge.svg)](https://github.com/Yanis897349/egress/actions/workflows/ci.yml)

Terraform automation for deploying and rotating a disposable personal
connectivity server on AWS Lightsail. Each deployment provides:

- VLESS + REALITY through Xray-core on TCP/443;
- Hysteria2 + Salamander through sing-box on UDP/443; and
- key-only SSH on TCP/22.

The central operational command is:

```bash
make rotate
```

It replaces the Lightsail instance and its firewall rules, waits for bootstrap,
retrieves fresh client profiles atomically, checks both services, and displays
new QR codes. The project does not create a static IP.

> [!CAUTION]
> Running this project creates billable, internet-facing AWS resources. Review
> every Terraform plan, monitor AWS charges, secure your credentials, and use
> the software only where permitted by applicable law, network policy, and
> provider terms.

## Region guides

Choose a guide for the location and AWS region you want to use:

- [Beijing via AWS Tokyo](docs/region/beijing.md)

The guide contains the region, availability zone, instance name, SSH key,
Lightsail bundle, client names, and troubleshooting details for that deployment.
Add other locations under `docs/region/` rather than putting regional defaults
in this README.

## Architecture and security model

Terraform stores infrastructure configuration and the public instance address.
Tunnel credentials are generated on the VPS during bootstrap and do not enter
Terraform configuration or state.

The REALITY private key remains in root-owned server storage and in the
root/Xray-readable Xray configuration. A separate root-only client manifest
contains the VLESS UUID, REALITY public key and short ID, Hysteria2 password,
and certificate fingerprint. The fetch workflow reads that manifest over
key-authenticated SSH, validates it locally, and renders two share links.

Xray-core is pinned and checksum-verified during bootstrap. Its REALITY inbound
accepts the client-version marker used by sing-box-based clients, including
Hiddify. REALITY and Hysteria2 can share port 443 because Xray listens on TCP
and sing-box listens on UDP.

Locally retrieved profiles are stored as:

```text
secrets/vless-reality.txt
secrets/hysteria2.txt
```

The directory is mode `0700` and each file is mode `0600`. It, Terraform state,
local tfvars, staging directories, runtime SSH host keys, and private key files
are ignored by Git.

SSH is reachable from any IPv4 address for recovery while traveling. Password
authentication, keyboard-interactive authentication, and root login are
disabled; only the configured Lightsail key can log in as `ubuntu`. Restricting
TCP/22 to known source CIDRs is a sensible future hardening step if stable
administrator addresses become available.

## Prerequisites

On macOS:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform awscli qrencode shellcheck jq
```

Configure AWS credentials using a provider-supported source such as
`aws configure`, AWS SSO, or `AWS_PROFILE`. The identity needs permission to
read and manage Lightsail instances, instance public ports, and the referenced
key pair. Reading month-to-date transfer with `make usage` additionally
requires the Cost Explorer `ce:GetCostAndUsage` permission. Do not put AWS
access keys in this repository.

Confirm the active identity before creating infrastructure:

```bash
aws sts get-caller-identity
```

Follow the selected [region guide](#region-guides) to create and upload an SSH
key, check active Lightsail blueprints and bundles, and set the regional values
in `terraform/terraform.tfvars`.

## Configuration

Copy the example configuration:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

The configuration accepts these settings:

| Setting | Purpose |
|---|---|
| `aws_region` | AWS region containing the Lightsail instance and key pair |
| `availability_zone` | Availability zone belonging to `aws_region` |
| `instance_name` | Name of the disposable Lightsail instance |
| `blueprint_id` | Active Lightsail OS blueprint |
| `bundle_id` | Active IPv4-compatible Lightsail plan |
| `key_pair_name` | Existing Lightsail key pair in `aws_region` |
| `reality_sni` | TLS 1.3-capable REALITY handshake target |

### Lightsail instance plans

This project uses Linux/Unix Lightsail bundles with a public IPv4 address. The
following table lists every general-purpose size, from Nano through 16Xlarge;
set its bundle ID as `bundle_id` in `terraform/terraform.tfvars`. Micro is the
checked-in example selection and is highlighted below.

| Plan | Bundle ID | USD/month | vCPUs | RAM | SSD | Monthly transfer |
|---|---|---:|---:|---:|---:|---:|
| Nano | `nano_3_0` | $5 | 2 | 0.5 GB | 20 GB | 1 TB |
| **Micro (example)** | **`micro_3_0`** | **$7** | **2** | **1 GB** | **40 GB** | **2 TB** |
| Small | `small_3_0` | $12 | 2 | 2 GB | 60 GB | 3 TB |
| Medium | `medium_3_0` | $24 | 2 | 4 GB | 80 GB | 4 TB |
| Large | `large_3_0` | $44 | 2 | 8 GB | 160 GB | 5 TB |
| Xlarge | `xlarge_3_0` | $84 | 4 | 16 GB | 320 GB | 6 TB |
| 2Xlarge | `2xlarge_3_0` | $164 | 8 | 32 GB | 640 GB | 7 TB |
| 4Xlarge | `4xlarge_3_0` | $384 | 16 | 64 GB | 1,280 GB | 8 TB |
| 8Xlarge | `8xlarge_3_0` | $884 | 32 | 128 GB | 1,280 GB | 9 TB |
| 12Xlarge | `12xlarge_3_0` | $1,324 | 48 | 192 GB | 1,280 GB | 10 TB |
| 16Xlarge | `16xlarge_3_0` | $1,764 | 64 | 256 GB | 1,280 GB | 10 TB |

These are AWS's published public-IPv4 monthly price ceilings and specifications;
usage is billed hourly up to the monthly amount. Both inbound and outbound
traffic consume the allowance, but AWS charges overage only for eligible
outbound traffic. Overage rates and some transfer allowances vary by region.
See the [AWS bundle table](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-bundles.html)
and [data-transfer rules](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-faq-data-transfer-allowance.html)
for details.

Prices, bundle availability, and specifications can change. Check the active
catalog in the deployment region before editing `bundle_id`:

```bash
AWS_REGION=your-aws-region
aws lightsail get-bundles \
  --region "${AWS_REGION}" \
  --query 'bundles[?isActive && contains(supportedPlatforms, `LINUX_UNIX`)].[bundleId,name,price,cpuCount,ramSizeInGb,diskSizeInGb,transferPerMonthInGb]' \
  --output table
```

`bundle_id` and `key_pair_name` are required. The checked-in example and
Terraform defaults correspond to the currently supported regional profile;
use its [region guide](docs/region/beijing.md) for the exact values and
verification commands.

The REALITY target must be a DNS hostname reachable from the VPS that accepts a
compatible TLS 1.3 handshake on port 443. Bootstrap performs both a direct TLS
check and an end-to-end REALITY proxy request. A normal TLS handshake can
succeed even when a target's certificate flight is unsuitable for REALITY, so
test any override carefully.

Set `SSH_KEY` to the absolute path of the private key matching
`key_pair_name` when it differs from the deployment's default:

```bash
export SSH_KEY=/absolute/path/to/private-key
```

## Deploy and connect

Run the local checks, initialize Terraform, and review the proposed
infrastructure:

```bash
make check
make init
make plan
```

Deploy after reviewing the plan:

```bash
make deploy
```

Deployment applies Terraform, waits up to 15 minutes for SSH and bootstrap,
retrieves the profiles, checks the server, and displays QR codes. Override the
timeout when a region is slow:

```bash
WAIT_TIMEOUT_SECONDS=1200 make deploy
```

Import the two generated profiles into a compatible client and test them
separately: REALITY uses TCP/443 while Hysteria2 uses UDP/443. See the selected
region guide for tested client instructions and profile names.

Treat the profile files, PNG files, clipboard contents, and QR codes as
passwords. Do not commit them, send them over an untrusted channel, save QR
screenshots to cloud storage, or paste them into an online QR-code generator.
`make qr` renders them locally, saves both PNGs with mode `0600`, and replaces
existing PNGs atomically.

## Operations

```bash
make output  # Show Terraform outputs
make status  # Show bootstrap, Xray, sing-box, listeners, UFW, and BBR
make usage   # Show month-to-date inbound, outbound, and total transfer
make ssh     # Open an SSH session to the current instance
make fetch   # Atomically refresh local profiles
make qr      # Display QR codes and save PNG copies in secrets/
make wait    # Wait for an in-progress bootstrap
make rotate  # Replace the instance and retrieve fresh profiles
```

`make usage` reads the current AWS billing month, including transfer from
instances replaced by `make rotate`. It compares the regional inbound plus
outbound total with the current instance plan's allowance. Cost Explorer data
is estimated during the current month and can lag behind recent traffic. If the
AWS session has expired, reauthenticate it before running the command. It uses
the configured AWS region (Tokyo by default); set `AWS_REGION` when checking a
deployment in another region.

The first SSH connection uses trust on first use and records the host key in
`.runtime/known_hosts`. That file is local to the repository and is cleared
after an intentional instance replacement.

Rotation records the old address, replaces the instance and authoritative
Lightsail firewall resource, and waits for the new server to become healthy.
The active local profiles are replaced only after the new manifest renders
successfully. If AWS assigns the same IPv4 address, the new credentials are
saved but the command exits with a warning; rotate again if a different address
is required.

Do not stop and start the instance in the Lightsail console as an IP-rotation
workflow. Use `make rotate` so Terraform state and the runtime SSH host record
remain coordinated.

## Destroy and local cleanup

Destroying infrastructure is intentionally interactive:

```bash
make destroy
```

Destroying the instance does not delete local profiles. Remove them explicitly
when they are no longer needed:

```bash
make clean-secrets
```

Lightsail charges for resources while they exist. After destroying a
deployment, verify in the Lightsail console that no unmanaged instance or
static IP remains.

## Troubleshooting

Start with:

```bash
make status
make wait
```

The readiness workflow distinguishes a remote bootstrap failure from a timeout
and prints the bootstrap log and both service statuses whenever SSH is
available. The selected [region guide](#region-guides) contains the concrete
log path and manual diagnostic commands for that deployment.

Common causes of deployment failure are an inactive bundle or blueprint, a
missing regional key pair, a mismatched local private key, an unsuitable
REALITY target, insufficient AWS permissions, or TCP/22 filtering on the
administrator's current network.

If SSH works but one profile does not, run `make status`, test both transports,
and try from an independent connection before replacing the endpoint. Keep an
independent recovery connection available.

## Repository layout

```text
.
├── Makefile
├── README.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CODE_OF_CONDUCT.md
├── LICENSE
├── cloud-init/
│   └── setup.sh
├── docs/
│   └── region/
│       └── beijing.md
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
    ├── test-qr.sh
    ├── test-render-config.sh
    └── test-wait-ready.sh
```

## Contributing and license

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before
opening an issue or pull request, and report vulnerabilities according to
[SECURITY.md](SECURITY.md). Community participation is governed by the
[code of conduct](CODE_OF_CONDUCT.md).

Egress is available under the [MIT License](LICENSE). It is provided without
warranty; operators remain responsible for their infrastructure, costs,
security, and compliance.
