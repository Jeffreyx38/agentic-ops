output "table_name" {
  value       = aws_dynamodb_table.this.name
  description = "DynamoDB table name"
}

output "table_arn" {
  value       = aws_dynamodb_table.this.arn
  description = "DynamoDB table ARN"
}

output "ssm_table_name_path" {
  value       = aws_ssm_parameter.table_name.name
  description = "SSM parameter path for the table name"
}

output "ssm_table_arn_path" {
  value       = aws_ssm_parameter.table_arn.name
  description = "SSM parameter path for the table ARN"
}
