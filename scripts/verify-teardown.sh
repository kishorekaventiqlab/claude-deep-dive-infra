#!/usr/bin/env bash
# verify-teardown.sh <region>: every demo resource gone, checked by tag, by name prefix and by IAM path.
set -uo pipefail
region=$1; aws=${AWS_CMD:-aws}; failed=0
check() {
  local label=$1; shift
  local out; out=$("$aws" "$@" --region "$region" --output json 2>&1) || { echo "ERROR $label: $out"; failed=1; return; }
  if [ "$(echo "$out" | tr -d '[:space:]')" = "[]" ]; then echo "OK    $label"; else echo "LEFT  $label: $out"; failed=1; fi
}
check "sg by tag"        ec2 describe-security-groups --filters Name=tag:project,Values=cdd --query 'SecurityGroups[].GroupId'
check "sg by name"       ec2 describe-security-groups --filters 'Name=group-name,Values=cdd-demo-*' --query 'SecurityGroups[].GroupId'
check "volumes by tag"   ec2 describe-volumes --filters Name=tag:project,Values=cdd --query 'Volumes[].VolumeId'
check "volumes unattached untagged" ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[?!not_null(Tags)].VolumeId'
check "s3 by prefix"     s3api list-buckets --query "Buckets[?starts_with(Name, 'cdd-demo-')].Name"
check "iam by path"      iam list-policies --scope Local --path-prefix /cdd-demo/ --query 'Policies[].Arn'
check "tagged resources" resourcegroupstaggingapi get-resources --tag-filters Key=project,Values=cdd --query "ResourceTagMappingList[?!contains(ResourceARN, 'cdd-tfstate') && !contains(ResourceARN, ':role/cdd-') && !contains(ResourceARN, 'oidc-provider') && !contains(ResourceARN, ':budget')].ResourceARN"
exit $failed
