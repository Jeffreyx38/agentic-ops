terraform {
  required_version = ">= 1.6"
  backend "s3" {
    key     = "prod/s3-media.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Environment = "prod", ManagedBy = "terraform-pipeline" }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

module "s3_media" {
  source      = "../../modules/s3"
  env         = "prod"
  name_prefix = "media"
  tags        = { Team = "platform" }
}

module "dynamodb_sessions" {
  source      = "../../modules/dynamodb"
  env         = "prod"
  name_prefix = "sessions"
  tags        = { Team = "platform" }
}

output "media_bucket_name" { value = module.s3_media.bucket_name }
output "media_bucket_arn" { value = module.s3_media.bucket_arn }
output "sessions_table_name" { value = module.dynamodb_sessions.table_name }
output "sessions_table_arn" { value = module.dynamodb_sessions.table_arn }
