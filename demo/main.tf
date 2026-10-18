terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {
    key          = "demo/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { project = "cdd", layer = "demo", purpose = "claude-deep-dive-demo", teardown = "nightly" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_vpc" "default" { default = true }
data "aws_availability_zones" "available" { state = "available" }

# Finding: bucket-level public access block disabled. Not public: no policy, no ACL, no objects (deploy role denies them).
resource "aws_s3_bucket" "demo" {
  bucket        = "cdd-demo-findings-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Finding: SSH open to the internet. Attached to nothing; the deploy role cannot launch or attach.
resource "aws_security_group" "ssh_open" {
  name        = "cdd-demo-ssh-open"
  description = "Claude Deep Dive demo: deliberately open SSH, attached to nothing"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from anywhere (deliberate misconfiguration)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Finding: unencrypted EBS volume. Empty, unattached; the deploy role cannot attach it.
resource "aws_ebs_volume" "unencrypted" {
  availability_zone = data.aws_availability_zones.available.names[0]
  size              = 1
  type              = "gp3"
  encrypted         = false
  tags              = { Name = "cdd-demo-unencrypted" }
}

# Finding: customer-managed policy granting everything. Unattached; the deploy role cannot attach policies.
resource "aws_iam_policy" "wildcard" {
  name        = "cdd-demo-wildcard"
  path        = "/cdd-demo/"
  description = "Claude Deep Dive demo: deliberately over-broad, never attached"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]
  })
}
