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
  type    = string
  default = "us-east-1"
}

module "s3_media" {
  source      = "../../modules/s3"
  env         = "dev"
  name_prefix = "media"
  tags        = { Team = "platform" }
}

output "media_bucket_name" { value = module.s3_media.bucket_name }
output "media_bucket_arn"  { value = module.s3_media.bucket_arn }
