variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used in resource names and tags (lowercase, no spaces)."
  type        = string
  default     = "secure-cloud-tasks"
}

variable "environment" {
  description = "Deployment stage (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "common_tags" {
  description = "Extra tags applied to all taggable resources via provider default_tags."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of AZs to span (2 recommended for ALB + RDS subnet groups)."
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zone_count >= 2 && var.availability_zone_count <= 6
    error_message = "Use between 2 and 6 AZs."
  }
}

variable "enable_nat_ha" {
  description = "If true, one NAT Gateway per public subnet (HA, higher cost). If false, single NAT (typical dev / portfolio)."
  type        = bool
  default     = false
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "tasks"
}

variable "db_username" {
  description = "Master username for RDS (not 'admin' / 'root' — avoid reserved patterns)."
  type        = string
  default     = "taskapp"
}

variable "db_instance_class" {
  description = "RDS instance size."
  type        = string
  default     = "db.t3.micro"
}

variable "engine_version" {
  description = "RDS PostgreSQL engine_version (must exist in the target region)."
  type        = string
  default     = "16.3"
}

variable "ec2_instance_type" {
  description = "App tier EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "TCP port Gunicorn listens on (ALB forwards here)."
  type        = number
  default     = 5000
}

variable "enable_vpc_flow_logs" {
  description = "Send VPC flow logs to CloudWatch (adds cost; good for security demos)."
  type        = bool
  default     = false
}
