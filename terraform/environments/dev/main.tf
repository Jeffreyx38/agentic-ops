terraform {
  required_version = ">= 1.6"
  backend "s3" {
    # Injected by CI: -backend-config="bucket=$TF_STATE_BUCKET"
    #                 -backend-config="dynamodb_table=$TF_LOCK_TABLE"
    key     = "dev/s3-media.tfstate"
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
    tags = { Environment = "dev", ManagedBy = "terraform-pipeline" }
  }
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources in this environment"
}

module "s3_media" {
  source      = "../../modules/s3"
  env         = "dev"
  name_prefix = "media"
  tags        = { Team = "platform" }
}

module "vpc" {
  source              = "../../modules/vpc"
  env                 = "dev"
  flow_log_bucket_arn = "arn:aws:s3:::jzbx-flow-logs-dev-us-east-1"
  tags                = { Team = "platform" }
}

output "media_bucket_name" {
  value       = module.s3_media.bucket_name
  description = "S3 media bucket name"
}

output "media_bucket_arn" {
  value       = module.s3_media.bucket_arn
  description = "S3 media bucket ARN"
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID"
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnet_ids
  description = "Public subnet IDs"
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnet_ids
  description = "Private subnet IDs"
}
