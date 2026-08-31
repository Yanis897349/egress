#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=./scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_command aws
require_command jq

billing_region_code() {
  if [[ -n "${LIGHTSAIL_BILLING_REGION_CODE:-}" ]]; then
    printf '%s\n' "${LIGHTSAIL_BILLING_REGION_CODE}"
    return
  fi

  case "$1" in
    ap-east-1) printf 'APE1\n' ;;
    ap-northeast-1) printf 'APN1\n' ;;
    ap-northeast-2) printf 'APN2\n' ;;
    ap-south-1) printf 'APS3\n' ;;
    ap-southeast-1) printf 'APS1\n' ;;
    ap-southeast-2) printf 'APS2\n' ;;
    ap-southeast-3) printf 'APS4\n' ;;
    ap-southeast-5) printf 'APS7\n' ;;
    ca-central-1) printf 'CAN1\n' ;;
    eu-central-1) printf 'EUC1\n' ;;
    eu-north-1) printf 'EUN1\n' ;;
    eu-south-2) printf 'EUS2\n' ;;
    eu-west-1) printf 'EU\n' ;;
    eu-west-2) printf 'EUW2\n' ;;
    eu-west-3) printf 'EUW3\n' ;;
    sa-east-1) printf 'SAE1\n' ;;
    us-east-1) printf 'USE1\n' ;;
    us-east-2) printf 'USE2\n' ;;
    us-west-2) printf 'USW2\n' ;;
    *)
      die "Unknown Lightsail billing code for region $1. Set LIGHTSAIL_BILLING_REGION_CODE to the usage-type prefix shown on the AWS bill."
      ;;
  esac
}

billing_dates() {
  BILLING_START=$(date -u '+%Y-%m-01')
  if BILLING_END=$(date -u -v+1d '+%Y-%m-%d' 2>/dev/null); then
    return
  fi
  if BILLING_END=$(date -u -d tomorrow '+%Y-%m-%d' 2>/dev/null); then
    return
  fi
  die "Unable to calculate the Cost Explorer end date."
}

aws_region=${AWS_REGION:-${AWS_DEFAULT_REGION:-}}
if [[ -z "${aws_region}" ]]; then
  aws_region=$(aws configure get region || true)
fi
aws_region=${aws_region:-ap-northeast-1}

instances_json=""
if ! instances_json=$(aws lightsail get-instances --region "${aws_region}" --output json); then
  die "Unable to list Lightsail instances in ${aws_region}."
fi

instance_filter='any(.tags[]?; .key == "Role" and .value == "personal-connectivity") and any(.tags[]?; .key == "ManagedBy" and .value == "terraform")'
if [[ -n "${LIGHTSAIL_INSTANCE_NAME:-}" ]]; then
  instance_filter=".name == \$instance_name"
fi

instance_count=$(
  jq -r \
    --arg instance_name "${LIGHTSAIL_INSTANCE_NAME:-}" \
    "[.instances[]? | select(${instance_filter})] | length" \
    <<<"${instances_json}"
)
if ((instance_count == 0)); then
  die "No managed connectivity instance found in ${aws_region}. Set AWS_REGION and, if needed, LIGHTSAIL_INSTANCE_NAME."
fi
if ((instance_count > 1)); then
  die "Multiple managed connectivity instances found in ${aws_region}. Set LIGHTSAIL_INSTANCE_NAME to select one."
fi

instance_fields=$(
  jq -cer \
    --arg instance_name "${LIGHTSAIL_INSTANCE_NAME:-}" \
    "[.instances[]? | select(${instance_filter})][0] | {name, bundleId}" \
    <<<"${instances_json}"
)
instance_name=$(jq -r '.name' <<<"${instance_fields}")
bundle_id=$(jq -r '.bundleId' <<<"${instance_fields}")
[[ -n "${instance_name}" && "${instance_name}" != "null" ]] || die "Lightsail returned no instance name."
[[ -n "${bundle_id}" && "${bundle_id}" != "null" ]] || die "Lightsail returned no bundle ID."

region_code=$(billing_region_code "${aws_region}")
billing_dates

in_usage_type="${region_code}-TotalDataXfer-In-Bytes"
out_usage_type="${region_code}-TotalDataXfer-Out-Bytes"
usage_filter=$(
  jq -cn \
    --arg incoming "${in_usage_type}" \
    --arg outgoing "${out_usage_type}" \
    '{
      And: [
        {Dimensions: {Key: "SERVICE", Values: ["Amazon Lightsail"]}},
        {Dimensions: {Key: "USAGE_TYPE", Values: [$incoming, $outgoing]}}
      ]
    }'
)

usage_json=""
if ! usage_json=$(
  aws ce get-cost-and-usage \
    --time-period "Start=${BILLING_START},End=${BILLING_END}" \
    --granularity MONTHLY \
    --metrics UsageQuantity \
    --filter "${usage_filter}" \
    --group-by Type=DIMENSION,Key=USAGE_TYPE \
    --output json
); then
  die "Unable to read Cost Explorer usage. Reauthenticate AWS and ensure the identity has ce:GetCostAndUsage permission."
fi

metric_amount() {
  jq -er --arg usage_type "$1" '
    [
      .ResultsByTime[].Groups[]?
      | select(.Keys[0] == $usage_type)
      | .Metrics.UsageQuantity.Amount
      | tonumber
    ]
    | add // 0
  ' <<<"${usage_json}"
}

inbound_gb=$(metric_amount "${in_usage_type}")
outbound_gb=$(metric_amount "${out_usage_type}")
estimated=$(jq -r '[.ResultsByTime[].Estimated] | any' <<<"${usage_json}")

bundles_json=""
if ! bundles_json=$(aws lightsail get-bundles --region "${aws_region}" --include-inactive --output json); then
  die "Unable to read the Lightsail bundle allowance in ${aws_region}."
fi

allowance_gb=""
if ! allowance_gb=$(
  jq -er --arg bundle_id "${bundle_id}" '
    .bundles[]
    | select(.bundleId == $bundle_id)
    | .transferPerMonthInGb
  ' <<<"${bundles_json}"
); then
  die "Unable to find transfer allowance for Lightsail bundle ${bundle_id}."
fi

LC_ALL=C awk \
  -v inbound="${inbound_gb}" \
  -v outbound="${outbound_gb}" \
  -v allowance="${allowance_gb}" \
  -v instance="${instance_name}" \
  -v region="${aws_region}" \
  -v bundle="${bundle_id}" \
  -v start="${BILLING_START}" \
  -v estimated="${estimated}" '
  BEGIN {
    total = inbound + outbound
    percent = allowance > 0 ? total / allowance * 100 : 0
    difference = allowance - total

    printf "Month-to-date Lightsail transfer (from %s UTC)\n", start
    printf "Instance:  %s (%s)\n", instance, region
    printf "Inbound:   %.3f GB\n", inbound
    printf "Outbound:  %.3f GB\n", outbound
    printf "Total:     %.3f GB\n", total
    printf "Plan:      %s — %.0f GB/month\n", bundle, allowance
    printf "Used:      %.2f%%\n", percent
    if (difference >= 0) {
      printf "Remaining: %.3f GB\n", difference
    } else {
      printf "Above plan allowance: %.3f GB\n", -difference
    }
    if (estimated == "true") {
      print "Note: AWS marks the current billing data as estimated; reporting may lag."
    }
  }
'
