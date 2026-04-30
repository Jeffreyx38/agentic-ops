terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

locals {
  topic_name  = "${var.env}-${var.name_prefix}-sns"
  common_tags = merge(var.tags, {
    Environment = var.env
    ManagedBy   = "terraform-pipeline"
  })
}

resource "aws_sns_topic" "this" {
  name              = local.topic_name
  kms_master_key_id = "alias/aws/sns"
  tags              = local.common_tags
}

resource "aws_ssm_parameter" "topic_arn" {
  name  = "/app/${var.env}/sns/${var.name_prefix}-topic-arn"
  type  = "String"
  value = aws_sns_topic.this.arn
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "topic_name" {
  name  = "/app/${var.env}/sns/${var.name_prefix}-topic-name"
  type  = "String"
  value = aws_sns_topic.this.name
  tags  = local.common_tags
}
