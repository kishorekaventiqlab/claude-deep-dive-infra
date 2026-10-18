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
