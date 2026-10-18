output "investigate_role_arn" { value = aws_iam_role.investigate.arn }
output "plan_role_arn" { value = aws_iam_role.ci["plan"].arn }
output "deploy_role_arn" { value = aws_iam_role.ci["deploy"].arn }
output "teardown_role_arn" { value = aws_iam_role.ci["teardown"].arn }
output "state_bucket" { value = aws_s3_bucket.state.bucket }
