# Seoul deployment and migration from Hong Kong

This guide prepares Egress for AWS Lightsail in Seoul. Read the
[prerequisites and general workflow](../../README.md) first. For the current
Hong Kong deployment, follow [the migration sequence below](#replace-hong-kong-in-the-same-workspace)
before changing its local configuration.

## Regional names and configuration

| Item | Current Hong Kong deployment | Seoul destination |
|---|---|---|
| AWS region | `ap-east-1` | `ap-northeast-2` |
| Availability zone (verify in the account) | `ap-east-1a` | `ap-northeast-2a` |
| Lightsail instance | `hongkong-vpn` | `seoul-vpn` |
| Linux Micro bundle with public IPv4 | `micro_3_1` | `micro_3_0` |
| OS blueprint | `ubuntu_24_04` | `ubuntu_24_04` |
| Regional Lightsail key pair name | `beijing-vps` | `seoul-vps` |
| Local SSH private key | `~/.ssh/beijing-vps` | Same file, same key |
| REALITY client profile | `Hong Kong-REALITY` | `Seoul-REALITY` |
| Hysteria2 client profile | `Hong Kong-HY2` | `Seoul-HY2` |
| Usage command | `AWS_REGION=ap-east-1 make usage` | `AWS_REGION=ap-northeast-2 make usage` |

The Hong Kong column describes the previous repository example. Preserve the
actual source instance name, zone, bundle, and key if your deployment differs.
`seoul-vps` is a new regional name for the existing public key; it does not
require generating or renaming the private key.

Terraform resource addresses remain `aws_lightsail_instance.vpn` and
`aws_lightsail_instance_public_ports.vpn`. Shared tags (`Role`, `Environment`,
`ManagedBy`), service names (`xray`, `sing-box`), and local files under `secrets/`
are independent of the region. The bootstrap paths retain their historical
names so the same scripts can still inspect existing HK and Tokyo servers:
`/var/lib/beijing-vps/`, `/var/log/beijing-vps-bootstrap.log`, and the
`99-beijing-vps.conf` files under `/etc/sysctl.d/` and `/etc/ssh/sshd_config.d/`.
Those names do not select an AWS region or change the client profile labels.

## Verify Seoul availability

Use the same AWS account/profile that manages Hong Kong:

```bash
aws sts get-caller-identity

aws lightsail get-regions \
  --region ap-northeast-2 \
  --include-availability-zones \
  --query 'regions[?name==`ap-northeast-2`].availabilityZones[].zoneName' \
  --output table

aws lightsail get-blueprints \
  --region ap-northeast-2 \
  --query 'blueprints[?isActive && contains(blueprintId, `ubuntu`)].[blueprintId,name]' \
  --output table

aws lightsail get-bundles \
  --region ap-northeast-2 \
  --query 'bundles[?isActive && contains(supportedPlatforms, `LINUX_UNIX`) && publicIpv4AddressCount==`1`].{ID:bundleId,USD:price,CPU:cpuCount,RAM_GB:ramSizeInGb,SSD_GB:diskSizeInGb,Transfer_GB:transferPerMonthInGb}' \
  --output table
```

Seoul is enabled by default; it does not require Hong Kong's opt-in activation
step. Confirm `ap-northeast-2a`, `ubuntu_24_04`, and `micro_3_0` in the returned
catalog, and substitute available values if necessary. See
[AWS Lightsail regions](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-regions-and-availability-zones-in-amazon-lightsail.html).

The Micro IPv4 example provides 2 vCPUs, 1 GB RAM, 40 GB SSD, and 2 TB monthly
transfer in Seoul, with a published $7 monthly ceiling. Hong Kong's equivalent
has 1 TB transfer. Verify the live catalog before deployment; the repository
cannot guarantee account-specific availability. See the
[AWS bundle catalog](https://docs.aws.amazon.com/cli/latest/reference/lightsail/get-bundles.html)
and [regional pricing](https://aws.amazon.com/lightsail/pricing/).

## Reimport the same SSH key into Seoul

Keep the existing private key. Load it for non-interactive SSH:

```bash
export SSH_KEY="$HOME/.ssh/beijing-vps"
chmod 600 "$SSH_KEY"
ssh-add --apple-use-keychain "$SSH_KEY"
```

Confirm that its public key matches the file being imported. The following
command should produce no differences and exit successfully:

```bash
diff <(ssh-keygen -y -f "$SSH_KEY" | awk '{print $1, $2}') \
     <(awk '{print $1, $2}' "$SSH_KEY.pub")
```

If the `.pub` file is missing, recover only the public half from the existing
private key, then repeat the comparison:

```bash
ssh-keygen -y -f "$SSH_KEY" > "$SSH_KEY.pub"
```

Check whether the destination name already exists:

```bash
aws lightsail get-key-pairs \
  --region ap-northeast-2 \
  --query 'keyPairs[?name==`seoul-vps`].[name,fingerprint]' \
  --output table
```

If absent, import the public key under the Seoul name:

```bash
aws lightsail import-key-pair \
  --region ap-northeast-2 \
  --key-pair-name seoul-vps \
  --public-key-base64 "file://$SSH_KEY.pub"

aws lightsail get-key-pair \
  --region ap-northeast-2 \
  --key-pair-name seoul-vps \
  --query 'keyPair.{Name:name,Fingerprint:fingerprint,Region:location.regionName}'
```

Use the OpenSSH public key text with `file://`, as in the existing Hong Kong
workflow. Do not upload the private key or base64-encode the entire public key
file. The [provider implementation](https://github.com/hashicorp/terraform-provider-aws/blob/v6.63.0/internal/service/lightsail/key_pair.go#L141)
passes this public key text directly to the import API. The AWS identity needs
`lightsail:ImportKeyPair` in addition to the key read permissions. See
[the AWS import command](https://docs.aws.amazon.com/cli/latest/reference/lightsail/import-key-pair.html).

If `seoul-vps` already exists, verify that it represents this same public key
before using it. An existing name alone does not establish a match. If its
origin is uncertain, import your public key under an unused Seoul name and
set that name in `key_pair_name`; do not delete a key another instance may use.
The Hong Kong key remains in Hong Kong. Key pairs are imported through the
Lightsail API and referenced by Terraform, so no `terraform import` is needed
for the key and `make destroy` does not remove it.

## Seoul tfvars

For a new workspace with no managed instance, copy the example:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

The resulting configuration should be:

```hcl
aws_region        = "ap-northeast-2"
availability_zone = "ap-northeast-2a"
instance_name     = "seoul-vpn"
blueprint_id      = "ubuntu_24_04"
bundle_id         = "micro_3_0"
key_pair_name     = "seoul-vps"
reality_sni       = "www.cloudflare.com"
```

For an existing Hong Kong state, wait until step 4 below before replacing its
configuration. Keep any intentional REALITY target override only if it has
passed the bootstrap checks.

## Replace Hong Kong in the same workspace

This sequence includes downtime. Work in the checkout containing the current
Hong Kong `terraform/terraform.tfstate` and `terraform/terraform.tfvars`.
New worktrees do not inherit those ignored files. If necessary, first follow
[Moving between worktrees](../../README.md#moving-between-worktrees). An empty
state is not evidence that the Hong Kong instance has been destroyed.

1. Complete the Seoul catalog checks and SSH key import above. Stop concurrent
   Terraform operations and back up the current state and tfvars in a private
   location outside Git. Before planning, applying, or destroying, explicitly
   pin the source configuration in `terraform/terraform.tfvars`:

   ```hcl
   aws_region        = "ap-east-1"
   availability_zone = "ap-east-1a"
   instance_name     = "hongkong-vpn"
   blueprint_id      = "ubuntu_24_04"
   bundle_id         = "micro_3_1"
   key_pair_name     = "beijing-vps"
   reality_sni       = "www.cloudflare.com"
   ```

   Use the actual deployed values if different. The repository now defaults to
   Seoul, so omitted source values are unsafe. Do not switch the provider
   region while it still manages the Hong Kong resources.
2. Initialize and inspect the managed instance:

   ```bash
   make init
   make output
   terraform -chdir=terraform state show aws_lightsail_instance.vpn
   ```

   Confirm its region/zone, name, bundle, and key match the source tfvars.
   If the instance is missing from state, recover the original state before
   continuing; do not deploy a second instance accidentally.
3. With the Hong Kong tfvars still in place, destroy the source:

   ```bash
   make destroy
   ```

   Review the interactive plan: it must target the Hong Kong instance and its
   public-port rules. Wait for success and verify the instance is gone in the
   Hong Kong Lightsail console. If destruction fails, resolve it before
   proceeding. The Make target clears the local SSH host record after removal.
4. Copy the Seoul example into `terraform/terraform.tfvars`, adjusting the
   verified zone, bundle, and key name as needed. Keep the state produced by
   the successful destroy. Do not delete it or restore the old state backup.
5. Follow [Deploy and validate](#deploy-and-validate) below. Use `make deploy`
   for the first Seoul instance; `make rotate` requires an existing instance.

To validate Seoul before taking HK offline, use a separate checkout with its
own empty state and Seoul tfvars, keeping Hong Kong's managing checkout intact.
After both Seoul profiles work, destroy HK from its original checkout with its
explicit HK settings. Both instances incur charges during the overlap.

If Seoul deployment fails after HK was destroyed, fix the Seoul configuration
and retry `make plan` / `make deploy`. To return to HK, first destroy any
partially created Seoul resources using the Seoul configuration, then restore
the HK **tfvars only** and redeploy. A state backup cannot resurrect a deleted
server; rollback creates a new IP and new tunnel credentials as well.

## Deploy and validate

```bash
make check
make plan
```

Review a plan creating `seoul-vpn` in `ap-northeast-2`, using the imported
`seoul-vps` key, with TCP/22, TCP/443, and UDP/443 public-port rules and no static
IP. Then run:

```bash
make deploy
AWS_REGION=ap-northeast-2 make usage
```

Deployment waits for bootstrap, fetches profiles, checks services, and renders
QR codes. Reimport both generated profiles into every client: `Seoul-REALITY`
and `Seoul-HY2`. See the [device import instructions](tokyo.md#connect-client-devices),
using the Seoul names. The SSH key is reused, but the public IP and tunnel
credentials are newly generated. Existing HK profiles cannot connect to Seoul.

Test both transports separately from the intended network. With each profile
connected, `https://checkip.amazonaws.com` should match `vpn_ip` from
`make output`. Remove the old HK profiles once both Seoul profiles work.

`make usage` honors AWS environment/CLI settings before its Seoul fallback.
Keep `AWS_REGION=ap-northeast-2` explicit if the CLI still defaults to HK.
Profile naming reads the deployed zone from Terraform state and does not use
that CLI default. HK transfer is not included in the Seoul usage report.

For SSH failures, check `key_pair_name = "seoul-vps"` in Seoul and
`SSH_KEY="$HOME/.ssh/beijing-vps"` locally, including the loaded agent key.
For an unavailable bundle, rerun `get-bundles` in Seoul; do not retain HK's
`micro_3_1` in the Seoul tfvars. For bootstrap diagnostics:

```bash
make status
make wait
make ssh
sudo tail -n 200 /var/log/beijing-vps-bootstrap.log
sudo systemctl status xray sing-box --no-pager
```

After subsequent `make rotate` operations, reimport both profiles again.
When Seoul is no longer needed, run `make destroy` from its managing checkout,
verify removal in Seoul, and run `make clean-secrets` for local profile cleanup.
