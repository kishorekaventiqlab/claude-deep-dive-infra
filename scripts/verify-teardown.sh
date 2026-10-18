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
# The tagging API is an eventually consistent index: it can list a resource for a while after deletion. So every ARN it
# returns is checked against the owning service; only an explicit "not found" counts as gone (a refused or failed check
# is reported, never treated as gone).
exists() {   # exists <arn>: prints yes | no | error:<message>
  local arn=$1 out rc
  case "$arn" in
    arn:aws:ec2:*:volume/*)         out=$("$aws" ec2 describe-volumes --region "$region" --volume-ids "${arn##*/}" 2>&1); rc=$? ;;
    arn:aws:ec2:*:security-group/*) out=$("$aws" ec2 describe-security-groups --region "$region" --group-ids "${arn##*/}" 2>&1); rc=$? ;;
    arn:aws:s3:::*)                 out=$("$aws" s3api head-bucket --bucket "${arn#arn:aws:s3:::}" --region "$region" 2>&1); rc=$? ;;
    arn:aws:iam::*:policy/*)        out=$("$aws" iam get-policy --policy-arn "$arn" 2>&1); rc=$? ;;
    *) echo yes; return ;;
  esac
  if [ $rc -eq 0 ]; then echo yes
  elif echo "$out" | grep -qE 'NotFound|NoSuchEntity|NoSuchBucket|\(404\)|Not Found'; then echo no
  else echo "error:$(echo "$out" | tail -1)"; fi
}
tagged=$("$aws" resourcegroupstaggingapi get-resources --region "$region" --tag-filters Key=project,Values=cdd \
  --query "ResourceTagMappingList[?!contains(ResourceARN, 'cdd-tfstate') && !contains(ResourceARN, ':role/cdd-') && !contains(ResourceARN, 'oidc-provider') && !contains(ResourceARN, ':budget')].ResourceARN" \
  --output text 2>&1) || { echo "ERROR tagged resources: $tagged"; failed=1; tagged=""; }
left=""; stale=""
for arn in $tagged; do
  [ "$arn" = None ] && continue
  case "$(exists "$arn")" in
    yes) left="$left $arn" ;;
    no)  stale="$stale $arn" ;;
    error:*) echo "ERROR existence check for $arn: $(exists "$arn" | cut -d: -f2-)"; failed=1 ;;
  esac
done
if [ -n "$left" ]; then echo "LEFT  tagged resources:$left"; failed=1
else echo "OK    tagged resources${stale:+ (stale index entries, confirmed deleted:$stale)}"; fi
exit $failed
