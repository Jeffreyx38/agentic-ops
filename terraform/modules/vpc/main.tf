terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    Environment = var.env
    ManagedBy   = "terraform-pipeline"
    Team        = "platform"
    Layer       = "networking"
  })

  # Public subnets keyed by "public-<az>"
  public_subnets = {
    for i, az in var.azs : "public-${az}" => {
      cidr = var.public_subnet_cidrs[i]
      az   = az
    }
  }

  # Private subnets keyed by "private-<az>"
  private_subnets = {
    for i, az in var.azs : "private-${az}" => {
      cidr = var.private_subnet_cidrs[i]
      az   = az
    }
  }

  # dev: 1 NAT in first AZ; prod: 1 NAT per AZ
  nat_azs = var.env == "prod" ? var.azs : [var.azs[0]]

  # Maps each AZ to the NAT AZ it should route through.
  # prod: same AZ; dev: all AZs route through the single NAT AZ.
  private_rt_nat_az = {
    for az in var.azs :
    az => contains(local.nat_azs, az) ? az : local.nat_azs[0]
  }
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  # prevent_destroy is set for all environments — VPCs are foundational resources
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.env}-vpc"
  })
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.env}-igw"
  })
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.env}-${each.key}"
    Type = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.env}-${each.key}"
    Type = "private"
  })
}

# ---------------------------------------------------------------------------
# Elastic IPs for NAT Gateways
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.env}-nat-eip-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# NAT Gateways (dev: 1 in first AZ; prod: 1 per AZ)
# ---------------------------------------------------------------------------
resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id     = aws_eip.nat[each.key].id
  subnet_id         = aws_subnet.public["public-${each.key}"].id
  connectivity_type = "public"

  tags = merge(local.common_tags, {
    Name = "${var.env}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Public Route Table (shared across all public subnets)
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.env}-public-rt"
  })
}

# Separate aws_route resource — inline route{} blocks are deprecated in provider 5.x
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Private Route Tables (1 per AZ)
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  for_each = toset(var.azs)

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.env}-private-rt-${each.key}"
  })
}

# Separate aws_route resources — inline route{} blocks are deprecated in provider 5.x
# dev: all private RTs route through the single NAT in azs[0]
# prod: each private RT routes through the AZ-local NAT
resource "aws_route" "private_nat" {
  for_each = toset(var.azs)

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.private_rt_nat_az[each.key]].id
}

resource "aws_route_table_association" "private" {
  for_each = local.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.value.az].id
}

# ---------------------------------------------------------------------------
# VPC Flow Logs
# ---------------------------------------------------------------------------
resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.env == "prod" ? "ALL" : "REJECT"
  log_destination_type     = "s3"
  log_destination          = var.flow_log_bucket_arn
  max_aggregation_interval = 600

  tags = merge(local.common_tags, {
    Name = "${var.env}-vpc-flow-log"
  })
}

# ---------------------------------------------------------------------------
# Default Security Group — empty ingress/egress removes all default rules
# ---------------------------------------------------------------------------
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.env}-default-sg"
  })
}

# ---------------------------------------------------------------------------
# SSM Parameter exports
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/app/${var.env}/vpc/vpc-id"
  type  = "String"
  value = aws_vpc.this.id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "vpc_cidr" {
  name  = "/app/${var.env}/vpc/vpc-cidr"
  type  = "String"
  value = aws_vpc.this.cidr_block
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name  = "/app/${var.env}/vpc/public-subnet-ids"
  type  = "String"
  value = join(",", [for k in sort(keys(local.public_subnets)) : aws_subnet.public[k].id])
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "/app/${var.env}/vpc/private-subnet-ids"
  type  = "String"
  value = join(",", [for k in sort(keys(local.private_subnets)) : aws_subnet.private[k].id])
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "nat_gateway_id" {
  name  = "/app/${var.env}/vpc/nat-gateway-id"
  type  = "String"
  value = join(",", [for az in sort(local.nat_azs) : aws_nat_gateway.this[az].id])
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "public_route_table_id" {
  name  = "/app/${var.env}/vpc/public-route-table-id"
  type  = "String"
  value = aws_route_table.public.id
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "private_route_table_ids" {
  name  = "/app/${var.env}/vpc/private-route-table-ids"
  type  = "String"
  value = join(",", [for az in sort(var.azs) : aws_route_table.private[az].id])
  tags  = local.common_tags
}
