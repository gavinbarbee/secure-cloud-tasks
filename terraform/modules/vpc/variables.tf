variable "name_prefix" {
  description = "Prefix for Name tags and unique resource naming."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC IPv4 CIDR block."
  type        = string
}

variable "az_count" {
  description = "How many AZs to use (must be <= available in region)."
  type        = number
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs to CloudWatch."
  type        = bool
  default     = false
}
