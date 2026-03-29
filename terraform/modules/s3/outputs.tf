output "bucket_name" {
  value       = aws_s3_bucket.this.id
  description = "S3 bucket name"
}

output "bucket_arn" {
  value       = aws_s3_bucket.this.arn
  description = "S3 bucket ARN"
}

output "bucket_region" {
  value       = data.aws_region.current.name
  description = "AWS region where the bucket is deployed"
}

output "ssm_arn_path" {
  value       = aws_ssm_parameter.bucket_arn.name
  description = "SSM parameter path for the bucket ARN"
}

output "ssm_name_path" {
  value       = aws_ssm_parameter.bucket_name.name
  description = "SSM parameter path for the bucket name"
}
