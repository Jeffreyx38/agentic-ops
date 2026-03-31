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
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources in this environment"
}

module "s3_media" {
  source      = "../../modules/s3"
  env         = "prod"
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
