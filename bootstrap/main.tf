terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region  = var.region
  profile = var.admin_profile
  default_tags { tags = { project = "cdd", layer = "bootstrap" } }
}

data "aws_caller_identity" "current" {}
data "aws_vpc" "default" { default = true }

locals {
  account  = data.aws_caller_identity.current.account_id
  repo     = "repo:${var.github_owner}/${var.infra_repo}"
  oidc_url = "token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_s3_bucket" "state" {
  bucket = "cdd-tfstate-${local.account}"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_budgets_budget" "monthly" {
  name         = "cdd-sandbox-monthly"
  budget_type  = "COST"
  limit_amount = var.budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# Read-only investigation role. Deviation from PLAN.md (P1c, 2026-10-17): it trusts the sandbox admin IAM user that
# Claude Code works with, instead of OrganizationAccountAccessRole.
resource "aws_iam_role" "investigate" {
  name = "cdd-investigate"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${local.account}:user/${var.admin_user_name}" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "investigate" {
  for_each   = toset(["arn:aws:iam::aws:policy/SecurityAudit", "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"])
  role       = aws_iam_role.investigate.name
  policy_arn = each.value
}

# Prowler's published additions policy, unmodified (tag 5.45.0, SHA-256 recorded in the evidence manifest).
resource "aws_iam_role_policy" "investigate_prowler" {
  name   = "prowler-additions"
  role   = aws_iam_role.investigate.id
  policy = file("${path.module}/prowler-additions-policy.json")
}

# The additions policy includes one write action, securityhub:BatchImportFindings (Prowler's optional Security Hub
# export). The investigation role stays strictly read-only.
resource "aws_iam_role_policy" "investigate_no_writes" {
  name = "read-only-guard"
  role = aws_iam_role.investigate.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "NoSecurityHubImport", Effect = "Deny", Action = ["securityhub:BatchImportFindings"], Resource = "*" }]
  })
}

# CI roles: each trusts one exact GitHub OIDC subject.
locals {
  ci_roles = {
    plan     = "${local.repo}:ref:refs/heads/main"
    deploy   = "${local.repo}:environment:sandbox"
    teardown = "${local.repo}:environment:sandbox-teardown"
  }
}

resource "aws_iam_role" "ci" {
  for_each = local.ci_roles
  name     = "cdd-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
          "${local.oidc_url}:sub" = each.value
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.ci["plan"].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "ci" {
  for_each = local.ci_roles
  name     = "cdd-${each.key}"
  role     = aws_iam_role.ci[each.key].id
  policy   = local.ci_policies[each.key]
}
