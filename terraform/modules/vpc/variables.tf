variable "env" {
  type        = string
  description = "Deployment environment (dev | prod)"
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "azs" {
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  description = "Availability zones to deploy into (must have exactly 3 entries)"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for public subnets, one per AZ (index-matched to azs)"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  description = "CIDR blocks for private subnets, one per AZ (index-matched to azs)"
}

variable "flow_log_bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket used as the VPC Flow Logs destination"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged onto all resources"
}
