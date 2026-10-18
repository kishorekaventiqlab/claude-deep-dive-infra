#!/usr/bin/env bash
# simulate-ci-roles.sh: IAM policy simulator checks for the CI roles (PLAN.md Task 4 Step 3b), machine-checked.
# Each case: role, expected decision (allowed | explicitDeny | implicitDeny | deny = either deny), actions, resources,
# optional context entries. Prints OK/WRONG per action-resource pair; exits non-zero on any WRONG.
set -uo pipefail
P=${AWS_PROFILE_ADMIN:-aventiqlab-sdb-admin}
A=593002483805; R=ap-south-1
B=arn:aws:s3:::cdd-demo-findings-$A; ST=arn:aws:s3:::cdd-tfstate-$A
SG=arn:aws:ec2:$R:$A:security-group/sg-00000000000000000
VOL=arn:aws:ec2:$R:$A:volume/vol-00000000000000000
VPC_ID=$(aws ec2 describe-vpcs --region $R --profile "$P" --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
DEFAULT_VPC=arn:aws:ec2:$R:$A:vpc/$VPC_ID
OTHER_VPC=arn:aws:ec2:$R:$A:vpc/vpc-00000000000000000
REGION_CTX="ContextKeyName=aws:RequestedRegion,ContextKeyValues=$R,ContextKeyType=string"
role_arn() { echo "arn:aws:iam::$A:role/cdd-$1"; }
failed=0

sim() {   # sim <label> <role> <expected> <actions...> -- <resources...> [-- <context entries...>]
  local label=$1 role=$2 want=$3; shift 3
  local actions=() resources=() ctx=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do actions+=("$1"); shift; done; shift
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do resources+=("$1"); shift; done
  [ $# -gt 0 ] && { shift; ctx=("$@"); }
  local args=(iam simulate-principal-policy --profile "$P" --policy-source-arn "$(role_arn "$role")"
              --action-names "${actions[@]}" --resource-arns "${resources[@]}"
              --query 'EvaluationResults[].[EvalActionName,EvalResourceName,EvalDecision]' --output text)
  [ ${#ctx[@]} -gt 0 ] && args+=(--context-entries "${ctx[@]}")
  local out; out=$(aws "${args[@]}" 2>&1) || { echo "ERROR  $label: $out"; failed=1; return; }
  while IFS=$'\t' read -r action resource got; do
    local ok=no
    if [ "$want" = deny ]; then [[ $got == *Deny ]] && ok=yes; else [ "$got" = "$want" ] && ok=yes; fi
    if [ $ok = yes ]; then echo "OK     $label | $role | $action | $resource | $got"
    else echo "WRONG  $label | $role | $action | $resource | $got (wanted $want)"; failed=1; fi
  done <<< "$out"
}

sim "teardown deletes demo bucket"      teardown allowed      s3:PutBucketPublicAccessBlock s3:DeleteBucket -- $B
sim "teardown deletes demo objects"     teardown allowed      s3:DeleteObject s3:DeleteObjectVersion -- "$B/*"
sim "teardown cannot delete state"      teardown explicitDeny s3:DeleteObject s3:DeleteObjectVersion -- "$ST/demo/terraform.tfstate" "$ST/bootstrap/terraform.tfstate"
sim "deploy exposure guards"            deploy   explicitDeny s3:PutBucketPolicy ec2:RunInstances ec2:AttachVolume iam:AttachRolePolicy -- "*"
sim "deploy has no delete power"        deploy   deny         s3:DeleteBucket s3:DeleteObject s3:DeleteObjectVersion ec2:DeleteSecurityGroup ec2:DeleteVolume ec2:RevokeSecurityGroupIngress ec2:DeleteTags iam:DeletePolicy iam:DeletePolicyVersion -- "*" -- "$REGION_CTX"
sim "deploy creates demo bucket"        deploy   allowed      s3:CreateBucket s3:PutBucketPublicAccessBlock s3:PutBucketTagging -- $B
sim "deploy cannot touch state bucket"  deploy   deny         s3:PutBucketPublicAccessBlock s3:PutBucketTagging -- $ST
sim "deploy create SG untagged"         deploy   implicitDeny ec2:CreateSecurityGroup -- $SG -- "$REGION_CTX"
sim "deploy create volume untagged"     deploy   implicitDeny ec2:CreateVolume -- $VOL -- "$REGION_CTX"
sim "deploy create SG tagged"           deploy   allowed      ec2:CreateSecurityGroup -- $SG -- "$REGION_CTX" "ContextKeyName=aws:RequestTag/project,ContextKeyValues=cdd,ContextKeyType=string"
sim "deploy create volume tagged"       deploy   allowed      ec2:CreateVolume -- $VOL -- "$REGION_CTX" "ContextKeyName=aws:RequestTag/project,ContextKeyValues=cdd,ContextKeyType=string"
sim "deploy SG in default VPC"          deploy   allowed      ec2:CreateSecurityGroup -- $DEFAULT_VPC -- "$REGION_CTX"
sim "deploy SG in another VPC"          deploy   implicitDeny ec2:CreateSecurityGroup -- $OTHER_VPC -- "$REGION_CTX"
sim "deploy rules on own SG"            deploy   allowed      ec2:AuthorizeSecurityGroupIngress ec2:RevokeSecurityGroupEgress -- $SG -- "$REGION_CTX" "ContextKeyName=ec2:ResourceTag/project,ContextKeyValues=cdd,ContextKeyType=string"
sim "deploy rules on other SG"          deploy   implicitDeny ec2:AuthorizeSecurityGroupIngress ec2:RevokeSecurityGroupEgress -- $SG -- "$REGION_CTX" "ContextKeyName=ec2:ResourceTag/project,ContextKeyValues=other,ContextKeyType=string"
sim "deploy tags at create"             deploy   allowed      ec2:CreateTags -- $SG -- "$REGION_CTX" "ContextKeyName=ec2:CreateAction,ContextKeyValues=CreateSecurityGroup,ContextKeyType=string"
sim "deploy tags outside create"        deploy   implicitDeny ec2:CreateTags -- $SG -- "$REGION_CTX" "ContextKeyName=ec2:CreateAction,ContextKeyValues=ModifySecurityGroupRules,ContextKeyType=string"
sim "plan cannot write state"           plan     deny         s3:PutObject s3:DeleteObject -- "$ST/demo/terraform.tfstate"
sim "plan reads state"                  plan     allowed      s3:GetObject -- "$ST/demo/terraform.tfstate"
sim "plan uses lock file"               plan     allowed      s3:GetObject s3:PutObject s3:DeleteObject -- "$ST/demo/terraform.tfstate.tflock"

echo "simulate-ci-roles: $([ $failed -eq 0 ] && echo PASS || echo STOP)"; exit $failed
