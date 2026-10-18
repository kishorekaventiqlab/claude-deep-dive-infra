#!/usr/bin/env bash
# deploy-dryrun.sh: prove what cdd-deploy may and may not do, with EC2 dry runs only.
set -uo pipefail
failed=0
expect() {   # expect <allowed|denied> <label> <command...>
  local want=$1 label=$2; shift 2
  local out; out=$("$@" --dry-run 2>&1)
  if echo "$out" | grep -q DryRunOperation; then got=allowed
  elif echo "$out" | grep -qE 'UnauthorizedOperation|explicit deny'; then got=denied
  else echo "OTHER   $label: $out"; failed=1; return; fi
  if [ "$got" = "$want" ]; then echo "OK      $label: $got"; else echo "WRONG   $label: $got, wanted $want"; failed=1; fi
}
VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
DEFAULT_SG=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC Name=group-name,Values=default \
  --query 'SecurityGroups[0].GroupId' --output text)
AZ=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)
# A real, current Amazon-owned image in this region, so run-instances reaches its authorization check (a placeholder
# image id would fail validation first). Nothing is launched: every call below is a dry run.
AMI=$(aws ec2 describe-images --owners amazon \
  --filters 'Name=name,Values=al2023-ami-2023.*-x86_64' Name=state,Values=available Name=architecture,Values=x86_64 \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
case "$AMI" in ami-*) echo "image for the launch test: $AMI" ;; *) echo "OTHER   image lookup: $AMI"; echo "deploy-dryrun: STOP"; exit 1 ;; esac
TAG_SG='ResourceType=security-group,Tags=[{Key=project,Value=cdd}]'
TAG_VOL='ResourceType=volume,Tags=[{Key=project,Value=cdd}]'
expect denied  "create security group, no tag"   aws ec2 create-security-group --group-name cdd-dryrun --description dryrun --vpc-id "$VPC"
expect allowed "create security group, tagged"   aws ec2 create-security-group --group-name cdd-dryrun --description dryrun --vpc-id "$VPC" --tag-specifications "$TAG_SG"
expect denied  "create volume, no tag"           aws ec2 create-volume --availability-zone "$AZ" --size 1 --volume-type gp3
expect allowed "create volume, tagged"           aws ec2 create-volume --availability-zone "$AZ" --size 1 --volume-type gp3 --tag-specifications "$TAG_VOL"
expect denied  "ingress rule on default SG"      aws ec2 authorize-security-group-ingress --group-id "$DEFAULT_SG" --protocol tcp --port 22 --cidr 0.0.0.0/0
expect denied  "revoke egress on default SG"     aws ec2 revoke-security-group-egress --group-id "$DEFAULT_SG" --protocol -1 --cidr 0.0.0.0/0
expect denied  "tag the default SG"              aws ec2 create-tags --resources "$DEFAULT_SG" --tags Key=project,Value=cdd
expect denied  "delete the default SG"           aws ec2 delete-security-group --group-id "$DEFAULT_SG"
expect denied  "launch an instance"              aws ec2 run-instances --image-id "$AMI" --instance-type t3.micro
echo "deploy-dryrun: $([ $failed -eq 0 ] && echo PASS || echo STOP)"; exit $failed
