variable "env" {
  type        = string
  description = "Deployment environment (dev | prod | test)"
  validation {
    condition     = contains(["dev", "prod", "test"], var.env)
    error_message = "env must be dev, prod, or test."
  }
}

variable "name_prefix" {
  type        = string
  description = "Short name used in resource names (e.g. media, logs, assets)"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric with hyphens only."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged onto all resources"
}

variable "mfa_delete" {
  type        = string
  default     = "Disabled"
  description = "Enable MFA Delete on the bucket versioning configuration. Valid values: Enabled or Disabled."
  validation {
    condition     = contains(["Enabled", "Disabled"], var.mfa_delete)
    error_message = "mfa_delete must be either Enabled or Disabled."
  }
}
