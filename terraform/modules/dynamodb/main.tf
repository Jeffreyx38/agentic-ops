terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_kms_key" "dynamodb" {
  key_id = "alias/aws/dynamodb"
}

locals {
  table_name = "${var.env}-${var.name_prefix}-dynamodb"
  common_tags = merge(var.tags, {
    Environment = var.env
    ManagedBy   = "terraform-pipeline"
  })
}

resource "aws_dynamodb_table" "this" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = data.aws_kms_key.dynamodb.arn
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = local.common_tags
}

resource "aws_ssm_parameter" "table_name" {
  name  = "/app/${var.env}/${var.name_prefix}/table-name"
  type  = "String"
  value = aws_dynamodb_table.this.name
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "table_arn" {
  name  = "/app/${var.env}/${var.name_prefix}/table-arn"
  type  = "String"
  value = aws_dynamodb_table.this.arn
  tags  = local.common_tags
}
