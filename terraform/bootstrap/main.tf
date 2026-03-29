terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "env" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "aws_region"           { type = string; default = "us-east-1" }
variable "github_repo"          { type = string; description = "org/repo e.g. acme/infrastructure" }
variable "create_oidc_provider" { type = bool;   default = true }

provider "aws" { region = var.aws_region }

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "tf-state-${var.env}-${data.aws_caller_identity.current.account_id}"
  table_name  = "tf-locks-${var.env}"
}

# ── State bucket ──────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "state" {
  bucket        = local.bucket_name
  force_destroy = false
  tags          = { Environment = var.env, ManagedBy = "terraform-bootstrap", Purpose = "terraform-state" }
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

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket     = aws_s3_bucket.state.id
  depends_on = [aws_s3_bucket_versioning.state]
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    noncurrent_version_expiration { noncurrent_days = 90 }
  }
}

# ── DynamoDB lock table ────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute    { name = "LockID"; type = "S" }
  point_in_time_recovery { enabled = true }
  tags         = { Environment = var.env, ManagedBy = "terraform-bootstrap", Purpose = "terraform-state-locking" }
}

# ── GitHub Actions OIDC ────────────────────────────────────────────────────────
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  oidc_arn = var.create_oidc_provider ? (
    aws_iam_openid_connect_provider.github[0].arn
  ) : data.aws_iam_openid_connect_provider.github[0].arn
}

resource "aws_iam_role" "github_actions" {
  name = "GitHubActionsDeployRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*" }
      }
    }]
  })
  tags = { ManagedBy = "terraform-bootstrap" }
}

resource "aws_iam_role_policy" "deploy" {
  name = "TerraformDeployPolicy"
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow"; Action = ["s3:*"]; Resource = "*" },
      { Effect = "Allow"; Action = ["ssm:GetParameter*", "ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource"]; Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/app/*" },
      { Effect = "Allow"; Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]; Resource = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"] },
      { Effect = "Allow"; Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]; Resource = aws_dynamodb_table.locks.arn },
      { Effect = "Allow"; Action = ["iam:CreateRole", "iam:DeleteRole", "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:GetRole", "iam:PassRole", "iam:TagRole"]; Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*" }
    ]
  })
}

output "state_bucket_name"        { value = aws_s3_bucket.state.id }
output "lock_table_name"          { value = aws_dynamodb_table.locks.name }
output "github_actions_role_arn"  { value = aws_iam_role.github_actions.arn }
