output "vpc_id" {
  value       = aws_vpc.this.id
  description = "VPC ID"
}

output "vpc_cidr" {
  value       = aws_vpc.this.cidr_block
  description = "VPC CIDR block"
}

output "public_subnet_ids" {
  value       = [for k in sort(keys(local.public_subnets)) : aws_subnet.public[k].id]
  description = "List of public subnet IDs (sorted by AZ)"
}

output "private_subnet_ids" {
  value       = [for k in sort(keys(local.private_subnets)) : aws_subnet.private[k].id]
  description = "List of private subnet IDs (sorted by AZ)"
}

output "nat_gateway_ids" {
  value       = [for az in sort(local.nat_azs) : aws_nat_gateway.this[az].id]
  description = "List of NAT gateway IDs (1 in dev, 3 in prod)"
}

output "public_route_table_id" {
  value       = aws_route_table.public.id
  description = "ID of the shared public route table"
}

output "private_route_table_ids" {
  value       = [for az in sort(var.azs) : aws_route_table.private[az].id]
  description = "List of private route table IDs (one per AZ, sorted)"
}

output "internet_gateway_id" {
  value       = aws_internet_gateway.this.id
  description = "Internet Gateway ID"
}

output "default_security_group_id" {
  value       = aws_default_security_group.this.id
  description = "ID of the default security group (all rules removed)"
}
