# Hong Kong deployment

This guide configures Egress with an AWS Lightsail instance in Hong Kong
(`ap-east-1`). The repository defaults now target Seoul; use the explicit
Hong Kong configuration below. This guide uses the Micro bundle (`micro_3_1`)
and Ubuntu 24.04. Generated profiles are named `Hong Kong-REALITY` and
`Hong Kong-HY2`, using the deployed instance's region from Terraform state.

To migrate the current Hong Kong deployment to Seoul, follow the
[Seoul migration guide](seoul.md#replace-hong-kong-in-the-same-workspace).

Read the [general workflow and prerequisites](../../README.md) first. If this
workspace already manages Tokyo, follow
[Replace Tokyo in the same workspace](#replace-tokyo-in-the-same-workspace)
before changing its configuration or deploying Hong Kong.

## Enable the region

Authenticate with your usual AWS CLI profile or login workflow, then verify
the active identity:

```bash
aws sts get-caller-identity
```

Hong Kong is an opt-in region. Check its status:

```bash
aws account get-region-opt-status \
  --region-name ap-east-1 \
  --region us-east-1
```

If it reports `DISABLED`, enable it:

```bash
aws account enable-region \
  --region-name ap-east-1 \
  --region us-east-1
```

Wait until the status reports `ENABLED` before making Hong Kong Lightsail
requests. Enabling Hong Kong leaves Tokyo enabled and its instances running.
These account commands require `account:GetRegionOptStatus` and
`account:EnableRegion` permissions respectively; you can also enable the region
through AWS account settings. See [AWS's region guide](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-regions-and-availability-zones-in-amazon-lightsail.html).

## Check the zone, image, and bundles

List the zones available to your account and active Ubuntu blueprints:

```bash
aws lightsail get-regions \
  --region ap-northeast-1 \
  --include-availability-zones \
  --query 'regions[?name==`ap-east-1`].availabilityZones[].zoneName' \
  --output table

aws lightsail get-blueprints \
  --region ap-east-1 \
  --query 'blueprints[?isActive && contains(blueprintId, `ubuntu`)].[blueprintId,name]' \
  --output table

aws lightsail get-bundles \
  --region ap-east-1 \
  --query 'bundles[?isActive && contains(supportedPlatforms, `LINUX_UNIX`) && publicIpv4AddressCount==`1`].{ID:bundleId,USD:price,CPU:cpuCount,RAM_GB:ramSizeInGb,SSD_GB:diskSizeInGb,Transfer_GB:transferPerMonthInGb}' \
  --output table
```

Use a zone returned by the first command. Confirm `ubuntu_24_04` and your
chosen bundle are active. The bundle query includes all active Linux plans
with public IPv4, including available compute- and memory-optimized options.
IPv6-only bundles do not match this project's IPv4 configuration.

## Bundles

The following general-purpose Linux bundles include public IPv4. Prices are
published monthly ceilings in USD, with hourly billing. Hong Kong includes
half the standard transfer allowance; the values below already account for
that reduction. Check the live catalog above before deployment.

| Bundle ID | USD/month | vCPUs | RAM | SSD | Hong Kong transfer/month |
|---|---:|---:|---:|---:|---:|
| `nano_3_1` | $5 | 2 | 0.5 GB | 20 GB | 0.5 TB |
| **`micro_3_1` (example)** | **$7** | **2** | **1 GB** | **40 GB** | **1 TB** |
| `small_3_1` | $12 | 2 | 2 GB | 60 GB | 1.5 TB |
| `medium_3_1` | $24 | 2 | 4 GB | 80 GB | 2 TB |
| `large_3_1` | $44 | 2 | 8 GB | 160 GB | 2.5 TB |
| `xlarge_3_1` | $84 | 4 | 16 GB | 320 GB | 3 TB |
| `2xlarge_3_1` | $164 | 8 | 32 GB | 640 GB | 3.5 TB |
| `4xlarge_3_1` | $384 | 16 | 64 GB | 1,280 GB | 4 TB |
| `8xlarge_3_1` | $884 | 32 | 128 GB | 1,280 GB | 4.5 TB |
| `12xlarge_3_1` | $1,324 | 48 | 192 GB | 1,280 GB | 5 TB |
| `16xlarge_3_1` | $1,764 | 64 | 256 GB | 1,280 GB | 5 TB |

Sources: [AWS bundle specifications](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-bundles.html)
and [regional pricing allowances](https://aws.amazon.com/lightsail/pricing/).

`micro_3_1` retains the original Tokyo deployment's size. Hong Kong uses
different bundle IDs from Tokyo: its Micro IPv4 bundle is `micro_3_1`, while Tokyo uses `micro_3_0`. `small_3_1` and
`medium_3_1` offer more memory and transfer if needed.

Both inbound and outbound traffic consume the allowance. A proxied download
enters and leaves the server, so budget roughly twice the downloaded data.
Eligible outbound overage in Hong Kong costs $0.09/GB. Replacing an instance
does not reset its bundle's regional monthly transfer usage. See
[AWS transfer rules](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-faq-data-transfer-allowance.html).

## SSH key

Lightsail key pairs are regional. You can reuse your existing local
`~/.ssh/beijing-vps` key by importing its public key into Hong Kong under the
same name. First check whether it is already present:

```bash
aws lightsail get-key-pairs --region ap-east-1
```

If the matching key is absent, import it:

```bash
aws lightsail import-key-pair \
  --region ap-east-1 \
  --key-pair-name beijing-vps \
  --public-key-base64 "file://$HOME/.ssh/beijing-vps.pub"
```

Pass the original OpenSSH public key text (`ssh-rsa AAAA... comment`) using
`file://`. Despite the argument name, do not base64-encode the entire file:
that produces an invalid key format. `fileb://` supplies bytes and fails CLI
validation for this string argument. The [Terraform AWS provider's import
implementation](https://github.com/hashicorp/terraform-provider-aws/blob/v6.63.0/internal/service/lightsail/key_pair.go#L141)
also passes the public key text directly to `PublicKeyBase64`.

For a new installation without a local key, follow the
[key creation instructions](tokyo.md#ssh-key-and-lightsail-key-pair) first,
then import the public key into Hong Kong as above.

Load the matching private key for non-interactive SSH:

```bash
export SSH_KEY="$HOME/.ssh/beijing-vps"
ssh-add --apple-use-keychain "$SSH_KEY"
```

If you choose another key, update both `SSH_KEY` and `key_pair_name` below.

## Configure a new Hong Kong deployment

For a workspace with no existing deployment, create
`terraform/terraform.tfvars` with these values:

```hcl
aws_region        = "ap-east-1"
availability_zone = "ap-east-1a"
instance_name     = "hongkong-vpn"
blueprint_id      = "ubuntu_24_04"
bundle_id         = "micro_3_1"
key_pair_name     = "beijing-vps"
reality_sni       = "www.cloudflare.com"
```

Replace `ap-east-1a` with a zone confirmed by the catalog command. Confirm the
blueprint and bundle as well. These explicit values override the repository's
Seoul defaults. Keep using the bootstrap-tested REALITY target unless you have
validated an alternative.

## Replace Tokyo in the same workspace

Use the checkout that currently contains Tokyo's `terraform/terraform.tfstate`
and `terraform/terraform.tfvars`, including your main checkout if that is where
Tokyo is managed. This sequence introduces downtime between deleting Tokyo and
bringing Hong Kong online.

1. Complete Hong Kong activation, catalog checks, and SSH key import above.
   Keep managing Tokyo with its actual deployed settings while doing those
   checks. The repository now defaults to Seoul, so older tfvars containing
   only `bundle_id` and `key_pair_name` no longer fully describe Tokyo. Before
   any Terraform operation, explicitly set these Tokyo values in the existing
   `terraform/terraform.tfvars`, retaining its actual bundle and key:

   ```hcl
   aws_region        = "ap-northeast-1"
   availability_zone = "ap-northeast-1a"
   instance_name     = "beijing-vpn"
   ```

   These are the original Tokyo deployment's values. If your deployment uses a
   different zone or name, use those recorded in its state instead.
2. Stop other Terraform operations for this deployment. Back up both local
   state and configuration in a private location outside Git.
3. With the original Tokyo configuration still in place, inspect and destroy
   Tokyo:

   ```bash
   make init
   make output
   make destroy
   ```

   Review the interactive destroy plan and confirm it targets the Tokyo
   instance and its firewall rules. Wait for successful destruction and verify
   the instance is gone from the Tokyo Lightsail console. If destruction fails,
   resolve it before proceeding.
4. Update `terraform/terraform.tfvars` to the Hong Kong configuration above.
   Keep the state file managed by Terraform; do not replace it with a different
   deployment's state or restore the pre-destruction backup.
5. Follow the deployment steps below in this same checkout.

Terraform removes Tokyo from state during destruction, then records Hong Kong
during deployment. Manual deletion in the console is unnecessary. Use
`make deploy` for this initial Hong Kong creation; `make rotate` requires an
existing managed instance.

To test Hong Kong while Tokyo stays online, create it in a separate checkout
with its own state and configuration instead. See
[Moving between worktrees](../../README.md#moving-between-worktrees) if you later
transfer management to another checkout. Both instances incur charges while
they exist.

## Deploy and connect

```bash
make check
make plan
```

Review a plan creating one Hong Kong instance and firewall rules for TCP/22,
TCP/443, and UDP/443. Then deploy:

```bash
make deploy
```

Deployment waits for bootstrap, retrieves fresh profiles, checks services, and
displays QR codes. Allow up to 15 minutes; set `WAIT_TIMEOUT_SECONDS=1200` for a
longer wait if needed.

Import the two profiles into Hiddify using its QR scanner or clipboard import.
See the [device instructions](tokyo.md#connect-client-devices), selecting
`Hong Kong-REALITY` and `Hong Kong-HY2` for this deployment. On macOS, copy each
profile separately:

```bash
pbcopy < secrets/vless-reality.txt
# Import in the client, then copy and import the second profile.
pbcopy < secrets/hysteria2.txt
```

Test each profile from your intended network. With the client connected,
`https://checkip.amazonaws.com` should show the address from `make output`.
Remove old Tokyo profiles once the replacement is working.

## Operations and troubleshooting

```bash
make status
make rotate
AWS_REGION=ap-east-1 make usage
```

Run `make rotate` only when you intend to replace the Hong Kong instance and
generate new credentials. Reimport both profiles after every rotation.
For an existing deployment that only needs updated display names, run
`make fetch` and `make qr`, then reimport the profiles.

The usage script uses AWS CLI/environment region settings, so specify
`AWS_REGION=ap-east-1` even when your default is Tokyo. Profile naming instead
reads the deployed instance's region from Terraform state.

If creation fails with `The specified bundle does not exist in this region`,
rerun the regional `get-bundles` command above and update `bundle_id` in your
local `terraform/terraform.tfvars`. For Hong Kong Micro with public IPv4, use
`micro_3_1`. Updating the checked-in example does not update an existing local
tfvars file. Run `make plan`, review it, then retry `make deploy`.

If Hong Kong API calls return `UnrecognizedClientException`, verify your AWS
login and confirm the region status is `ENABLED`. Empty zone results can also
indicate that activation is incomplete. Check that the selected blueprint,
bundle, and SSH key exist in Hong Kong.

For bootstrap issues, use `make status` and `make wait`. The shared bootstrap
script retains its historical log path even in Hong Kong:

```bash
make ssh
sudo tail -n 200 /var/log/beijing-vps-bootstrap.log
sudo systemctl status xray sing-box --no-pager
```

Treat profiles and QR codes as passwords. When the Hong Kong deployment is no
longer needed, run `make destroy` from its managing checkout, then
`make clean-secrets` to remove local profiles and QR images.
