terraform {
  required_version = "~> 1.8.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# --- Remote state backend ---

resource "aws_s3_bucket" "state" {
  # checkov:skip=CKV_AWS_145: customer-managed KMS key - optional bonus item
  # checkov:skip=CKV_AWS_18: a dedicated access-log target bucket doubles this
  # bootstrap module's bucket count for marginal benefit - state changes are
  # already tracked via S3 versioning plus the DynamoDB lock table.
  # checkov:skip=CKV_AWS_144: cross-region replication is disproportionate
  # infrastructure (a second bucket in another region) for this exercise's
  # Terraform state bucket.
  # checkov:skip=CKV2_AWS_62: event notifications have no consumer here -
  # nothing in this project reacts to state-bucket object events.
  bucket = var.state_bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "state_lock" {
  name         = var.state_lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # checkov:skip=CKV_AWS_119: customer-managed KMS key - optional bonus item
  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = var.tags
}

# --- GitHub OIDC federation for CI/CD ---
# The OIDC provider is an account-level singleton. When staging and prod
# share one AWS account, only one environment's bootstrap should create it
# (manage_oidc_provider = true); the other reuses it via a data source.

data "aws_iam_openid_connect_provider" "github" {
  count = var.manage_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.manage_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = var.tags
}

locals {
  oidc_provider_arn = var.manage_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# --- Dedicated deployment role assumed by GitHub Actions via OIDC ---
# Scoped to this environment's own resources wherever the AWS action model
# allows resource-level ARNs. API Gateway's IAM model has no name-based ARNs
# for its management API (it authorizes by HTTP verb against generated
# resource IDs), so the apigateway statement below is the one place a
# wildcard is unavoidable rather than a shortcut.

resource "aws_iam_role" "deploy" {
  name = "${var.env}-terraform-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = local.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        # AWS requires the trust policy to evaluate 'sub' (or
        # 'job_workflow_ref'), scoped - it rejects a policy that relies only
        # on 'repository'. GitHub now embeds stable numeric owner/repo IDs
        # into 'sub' to prevent repojacking after a rename, e.g.
        # "repo:org@12345/repo@67890:environment:staging" instead of the
        # plain "repo:org/repo:environment:staging" it used to be. Matching
        # both forms keeps this portable (no hardcoded IDs) and correct
        # whichever format a given repo's tokens actually use.
        # 'repository' is kept alongside as a clean, exact-match belt to the
        # wildcarded 'sub' suspenders.
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud"        = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:repository" = "${var.github_org}/${var.github_repo}"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${var.github_org}/${var.github_repo}:*",
              "repo:${var.github_org}@*/${var.github_repo}@*:*",
            ]
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "deploy" {
  name = "${var.env}-terraform-deploy-policy"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.state_bucket_name}",
          "arn:aws:s3:::${var.state_bucket_name}/*",
        ]
      },
      {
        Sid      = "TerraformStateLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.state_lock_table}"
      },
      {
        Sid    = "ManageAppDynamoDbTable"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:ListTagsOfResource",
          "dynamodb:UpdateContinuousBackups",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTimeToLive",
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.env}-*"
      },
      {
        Sid    = "ManageAppLambda"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:ListTags",
          "lambda:ListVersionsByFunction",
          "lambda:GetFunctionCodeSigningConfig",
          "lambda:GetFunctionConcurrency",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy",
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.env}-*"
      },
      {
        Sid    = "ManageAppLambdaLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:ListTagsForResource",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.env}-*"
      },
      {
        # DescribeLogGroups has no resource-level permissions in CloudWatch
        # Logs' IAM action model at all - it's always called against "*",
        # regardless of which log group is actually being looked up. Terraform
        # calls it to check whether the log group already exists.
        Sid      = "DescribeLogGroupsGlobal"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      },
      {
        Sid    = "ManageAppIamRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PassRole",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.env}-*"
      },
      {
        # API Gateway's management API has no resource-name ARNs to scope by;
        # it authorizes via HTTP-verb pseudo-actions against the generic
        # /restapis path, plus a separate /tags/* path for tagging calls.
        # This is the one mandatory wildcard.
        Sid    = "ManageApiGateway"
        Effect = "Allow"
        Action = ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"]
        Resource = [
          "arn:aws:apigateway:${var.aws_region}::/restapis",
          "arn:aws:apigateway:${var.aws_region}::/restapis/*",
          "arn:aws:apigateway:${var.aws_region}::/tags/*",
        ]
      },
    ]
  })
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "state_lock_table" {
  value = aws_dynamodb_table.state_lock.name
}

output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}
