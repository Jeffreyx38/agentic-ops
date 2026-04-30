output "topic_name" {
  value       = aws_sns_topic.this.name
  description = "SNS topic name"
}

output "topic_arn" {
  value       = aws_sns_topic.this.arn
  description = "SNS topic ARN"
}

output "ssm_arn_path" {
  value       = aws_ssm_parameter.topic_arn.name
  description = "SSM parameter path for the topic ARN"
}

output "ssm_name_path" {
  value       = aws_ssm_parameter.topic_name.name
  description = "SSM parameter path for the topic name"
}
