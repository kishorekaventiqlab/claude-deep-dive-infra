variable "region" {
  type    = string
  default = "ap-south-1"
}
variable "github_owner" {
  type    = string
  default = "kishorekaventiqlab"
}
variable "infra_repo" {
  type    = string
  default = "claude-deep-dive-infra"
}
# GitHub sends immutable OIDC subjects for this repository ("use_immutable_subject": true):
# repo:<owner>@<owner id>/<repo>@<repo id>:... The numeric ids stop a re-created repository with the same name
# from inheriting the trust. Read 2026-10-18 from the GitHub API and from CloudTrail.
variable "github_owner_id" {
  type    = string
  default = "226353510"
}
variable "infra_repo_id" {
  type    = string
  default = "1423915375"
}
variable "admin_profile" {
  description = "The sandbox admin profile (Kishore's decision 2026-10-17: the IAM user aventiqlab-sandbox-admin, used by Claude Code)."
  type        = string
  default     = "aventiqlab-sdb-admin"
}
variable "admin_user_name" {
  type    = string
  default = "aventiqlab-sandbox-admin"
}
variable "budget_usd" {
  type = string
}
variable "alert_email" {
  type = string
}
