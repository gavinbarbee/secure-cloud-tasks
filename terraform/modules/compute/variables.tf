variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "app_security_group_id" {
  type = string
}

variable "iam_instance_profile_name" {
  type = string
}

variable "alb_target_group_arn" {
  type = string
}

variable "database_secret_arn" {
  type = string
}

variable "app_artifact_bucket" {
  type = string
}

variable "app_artifact_key" {
  type = string
}

variable "app_port" {
  type = number
}

variable "instance_type" {
  type = string
}
