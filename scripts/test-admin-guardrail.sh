#!/usr/bin/env bash
# test-admin-guardrail.sh [--before-attach]: checks the guardrail on aventiqlab-sandbox-admin (D-023 phase B).
# --before-attach: simulates the user's current policies PLUS the draft guardrail (nothing attached, no side effects).
# Without it: simulates the user's policies as attached. Exits non-zero on any WRONG.
set -uo pipefail
P=aventiqlab-sdb-admin; A=593002483805; R=ap-south-1
USER_ARN=arn:aws:iam::$A:user/aventiqlab-sandbox-admin
HERE=$(cd "$(dirname "$0")" && pwd)
EXTRA=()
if [ "${1:-}" = "--before-attach" ]; then
  # --policy-input-list takes a list of policy documents: pass the file's contents as one item (file:// would be
  # split into characters by the CLI).
  EXTRA=(--policy-input-list "$(cat "$HERE/../bootstrap/guardrails/aventiqlab-sandbox-admin-guardrail.json")")
fi
in_region()  { echo "ContextKeyName=aws:RequestedRegion,ContextKeyValues=$1,ContextKeyType=string"; }
failed=0
sim() {   # sim <label> <allowed|deny> <action> <resource> <region>
  local label=$1 want=$2 action=$3 resource=$4 region=$5 got
  got=$(aws iam simulate-principal-policy --profile $P --policy-source-arn $USER_ARN ${EXTRA[@]+"${EXTRA[@]}"} \
        --action-names "$action" --resource-arns "$resource" --context-entries "$(in_region "$region")" \
        --query 'EvaluationResults[0].EvalDecision' --output text 2>&1) || { echo "ERROR  $label: $(echo "$got" | tail -1 | cut -c1-200)"; failed=1; return; }
  if { [ "$want" = allowed ] && [ "$got" = allowed ]; } || { [ "$want" = deny ] && [[ $got == *Deny ]]; }; then
    echo "OK     $label: $got"
  else
    echo "WRONG  $label: $got (wanted $want)"; failed=1
  fi
}
ST=arn:aws:s3:::cdd-tfstate-$A
echo "== must stay allowed"
sim "assume read-only role"          allowed sts:AssumeRole               arn:aws:iam::$A:role/cdd-investigate $R
sim "read IAM"                       allowed iam:GetRole                  arn:aws:iam::$A:role/cdd-deploy $R
sim "run the IAM simulator"          allowed iam:SimulatePrincipalPolicy  arn:aws:iam::$A:role/cdd-deploy $R
sim "list state bucket"              allowed s3:ListBucket                $ST $R
sim "write bootstrap backup"         allowed s3:PutObject                 "$ST/bootstrap/terraform.tfstate" $R
sim "describe VPCs in Mumbai"        allowed ec2:DescribeVpcs             "*" $R
sim "validate a policy"              allowed access-analyzer:ValidatePolicy "*" $R
sim "view the budget"                allowed budgets:ViewBudget           "arn:aws:budgets::$A:budget/cdd-sandbox-monthly" us-east-1
sim "read CloudTrail history"        allowed cloudtrail:LookupEvents      "*" $R
echo "== must be denied"
sim "create a user"                  deny    iam:CreateUser               arn:aws:iam::$A:user/x $R
sim "create an access key"           deny    iam:CreateAccessKey          $USER_ARN $R
sim "create a role"                  deny    iam:CreateRole               arn:aws:iam::$A:role/x $R
sim "change a role's trust"          deny    iam:UpdateAssumeRolePolicy   arn:aws:iam::$A:role/cdd-deploy $R
sim "widen the read-only role"       deny    iam:AttachRolePolicy         arn:aws:iam::$A:role/cdd-investigate $R
sim "pass a role to a service"       deny    iam:PassRole                 arn:aws:iam::$A:role/cdd-deploy $R
sim "remove own guardrail"           deny    iam:DeleteUserPolicy         $USER_ARN $R
sim "rewrite own guardrail"          deny    iam:PutUserPolicy            $USER_ARN $R
sim "detach managed guardrail"       deny    iam:DetachUserPolicy         $USER_ARN $R
sim "new guardrail version"          deny    iam:CreatePolicyVersion      arn:aws:iam::$A:policy/cdd-guardrail $R
sim "switch guardrail version"       deny    iam:SetDefaultPolicyVersion  arn:aws:iam::$A:policy/cdd-guardrail $R
sim "leave the Organization"         deny    organizations:LeaveOrganization "*" us-east-1
sim "close the account"              deny    account:CloseAccount         "*" us-east-1
sim "change the budget"              deny    budgets:ModifyBudget         "arn:aws:budgets::$A:budget/cdd-sandbox-monthly" us-east-1
sim "stop CloudTrail logging"        deny    cloudtrail:StopLogging       "*" $R
sim "launch an instance"             deny    ec2:RunInstances             "*" $R
sim "work in us-east-1"              deny    ec2:DescribeVpcs             "*" us-east-1
sim "create a bucket in us-east-1"   deny    s3:CreateBucket              "arn:aws:s3:::cdd-x" us-east-1
echo "admin-guardrail: $([ $failed -eq 0 ] && echo PASS || echo STOP)"; exit $failed
