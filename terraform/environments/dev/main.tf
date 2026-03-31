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

output "media_bucket_name" {
  value       = module.s3_media.bucket_name
  description = "S3 media bucket name"
}

output "media_bucket_arn" {
  value       = module.s3_media.bucket_arn
  description = "S3 media bucket ARN"
}


module "s3_logs" {
  source                = "../../modules/s3"
  env                   = "dev"
  name_prefix           = "logs"
  lifecycle_expire_days = 30
  tags                  = { Team = "platform" }
}

output "logs_bucket_name" {
  value       = module.s3_logs.bucket_name
  description = "S3 logs bucket name"
}

output "logs_bucket_arn" {
  value       = module.s3_logs.bucket_arn
  description = "S3 logs bucket ARN"
}
