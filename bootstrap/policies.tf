locals {
  state_arn = aws_s3_bucket.state.arn
  state_key = "demo/terraform.tfstate"
  demo_s3   = ["arn:aws:s3:::cdd-demo-*", "arn:aws:s3:::cdd-demo-*/*"]
  demo_iam  = "arn:aws:iam::${local.account}:policy/cdd-demo/*"

  # S3 backend with use_lockfile: list the bucket, read/write the state key, read/write/delete only the lock key.
  # No CI role may delete the state, any version of it, or the bootstrap backup.
  state_list = {
    Sid      = "StateList"
    Effect   = "Allow"
    Action   = ["s3:ListBucket"]
    Resource = local.state_arn
  }
  state_read = {
    Sid      = "StateRead"
    Effect   = "Allow"
    Action   = ["s3:GetObject"]
    Resource = "${local.state_arn}/${local.state_key}"
  }
  state_rw = {
    Sid      = "StateReadWrite"
    Effect   = "Allow"
    Action   = ["s3:GetObject", "s3:PutObject"]
    Resource = "${local.state_arn}/${local.state_key}"
  }
  state_lock = {
    Sid      = "StateLockFile"
    Effect   = "Allow"
    Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    Resource = "${local.state_arn}/${local.state_key}.tflock"
  }
  state_protect_objects = {
    Sid      = "StateNeverDeleted"
    Effect   = "Deny"
    Action   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
    Resource = ["${local.state_arn}/${local.state_key}", "${local.state_arn}/bootstrap/*"]
  }
  state_protect_bucket = {
    Sid    = "StateBucketUntouchable"
    Effect = "Deny"
    Action = ["s3:DeleteBucket", "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration", "s3:PutBucketPolicy",
    "s3:PutBucketPublicAccessBlock"]
    Resource = local.state_arn
  }
  reads = {
    Sid      = "Read"
    Effect   = "Allow"
    Action   = ["ec2:Describe*", "iam:Get*", "iam:List*", "sts:GetCallerIdentity", "s3:ListAllMyBuckets", "tag:GetResources"]
    Resource = "*"
  }
  demo_s3_read = {
    Sid      = "DemoS3Read"
    Effect   = "Allow"
    Action   = ["s3:Get*", "s3:List*"]
    Resource = local.demo_s3
  }
  guards = {
    Sid    = "ExposureGuards"
    Effect = "Deny"
    Action = [
      "s3:PutBucketPolicy", "s3:PutBucketAcl", "s3:PutObjectAcl",
      "ec2:RunInstances", "ec2:AttachVolume", "ec2:CreateNetworkInterface", "ec2:ModifyNetworkInterfaceAttribute",
      "iam:AttachRolePolicy", "iam:AttachUserPolicy", "iam:AttachGroupPolicy",
      "iam:PutRolePolicy", "iam:PutUserPolicy", "iam:PutGroupPolicy",
      "iam:CreateRole", "iam:CreateUser", "iam:CreateAccessKey"
    ]
    Resource = "*"
  }
  no_demo_objects = {
    Sid      = "SyntheticOnlyNoObjects"
    Effect   = "Deny"
    Action   = ["s3:PutObject"]
    Resource = ["arn:aws:s3:::cdd-demo-*/*"]
  }

  ci_policies = {
    plan = jsonencode({
      Version = "2012-10-17"
      Statement = [
        local.state_list, local.state_read, local.state_lock, local.state_protect_objects, local.state_protect_bucket
      ]
    })
    deploy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        local.state_list, local.state_rw, local.state_lock, local.state_protect_objects, local.state_protect_bucket,
        local.reads, local.demo_s3_read, local.guards, local.no_demo_objects,
        # Scoped to the create workflow, not literally create-only: PutBucketPublicAccessBlock, PutBucketTagging,
        # AuthorizeSecurityGroupIngress and RevokeSecurityGroupEgress can modify a resource, so each is confined to
        # resources this project created (cdd-demo-* buckets; security groups tagged project=cdd at creation). The
        # role holds no delete permission; destruction belongs to cdd-teardown. Any action here must appear in the
        # Step 4b permission map as needed by a create, and the add-only plan check (Task 7) refuses any other plan.
        {
          Sid      = "DemoS3Create"
          Effect   = "Allow"
          Action   = ["s3:CreateBucket", "s3:PutBucketPublicAccessBlock", "s3:PutBucketTagging"]
          Resource = local.demo_s3
        },
        # CreateSecurityGroup authorises two resources in one request: the new security-group (where the tag
        # condition applies) and the VPC it is created in. Every resource in a request must be allowed, so the
        # VPC statement alone cannot authorise a creation: an untagged request fails on the security-group
        # resource. The VPC statement is limited to the default VPC only. Proven by the simulator (Task 4 Step 3b)
        # and, against real AWS including the SCP, by the EC2 dry-run tests (Task 7 Step 8).
        {
          Sid       = "DemoSgCreateTagged"
          Effect    = "Allow"
          Action    = ["ec2:CreateSecurityGroup"]
          Resource  = "arn:aws:ec2:${var.region}:${local.account}:security-group/*"
          Condition = { StringEquals = { "aws:RequestTag/project" = "cdd" } }
        },
        {
          Sid      = "DemoSgCreateInDefaultVpcOnly"
          Effect   = "Allow"
          Action   = ["ec2:CreateSecurityGroup"]
          Resource = "arn:aws:ec2:${var.region}:${local.account}:vpc/${data.aws_vpc.default.id}"
        },
        {
          Sid       = "DemoVolumeCreateTagged"
          Effect    = "Allow"
          Action    = ["ec2:CreateVolume"]
          Resource  = "arn:aws:ec2:${var.region}:${local.account}:volume/*"
          Condition = { StringEquals = { "aws:RequestTag/project" = "cdd" } }
        },
        {
          Sid      = "DemoEc2TagOnlyAtCreate"
          Effect   = "Allow"
          Action   = ["ec2:CreateTags"]
          Resource = "*"
          Condition = {
            StringEquals               = { "aws:RequestedRegion" = var.region }
            "ForAnyValue:StringEquals" = { "ec2:CreateAction" = ["CreateSecurityGroup", "CreateVolume"] }
          }
        },
        {
          Sid    = "DemoEc2RulesOnOwnGroups"
          Effect = "Allow"
          # RevokeSecurityGroupEgress: the AWS provider removes AWS's default allow-all egress rule right after
          # creating a security group. Both rule actions are limited to groups tagged project=cdd.
          Action    = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress"]
          Resource  = "arn:aws:ec2:${var.region}:${local.account}:security-group/*"
          Condition = { StringEquals = { "ec2:ResourceTag/project" = "cdd" } }
        },
        {
          Sid      = "DemoIamCreate"
          Effect   = "Allow"
          Action   = ["iam:CreatePolicy", "iam:TagPolicy"]
          Resource = local.demo_iam
        }
      ]
    })
    teardown = jsonencode({
      Version = "2012-10-17"
      Statement = [
        local.state_list, local.state_rw, local.state_lock, local.state_protect_objects, local.state_protect_bucket,
        local.reads, local.demo_s3_read, local.guards, local.no_demo_objects,
        {
          Sid    = "DeleteOnlyS3"
          Effect = "Allow"
          # DeleteBucketPublicAccessBlock is authorised by the s3:PutBucketPublicAccessBlock action (confirmed against
          # the Service Authorization Reference in Step 4b). Scoped to cdd-demo-* buckets only.
          Action   = ["s3:DeleteBucket", "s3:DeleteObject", "s3:DeleteObjectVersion", "s3:PutBucketPublicAccessBlock"]
          Resource = local.demo_s3
        },
        {
          Sid    = "DeleteOnlyEc2"
          Effect = "Allow"
          Action = ["ec2:DeleteSecurityGroup", "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
          "ec2:DeleteVolume"]
          Resource  = "*"
          Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }
        },
        {
          Sid      = "DeleteOnlyIam"
          Effect   = "Allow"
          Action   = ["iam:DeletePolicy", "iam:DeletePolicyVersion"]
          Resource = local.demo_iam
        }
      ]
    })
  }
}
