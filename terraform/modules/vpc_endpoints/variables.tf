variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_cidr" {
  description = "VPC CIDR allowed to reach interface endpoints on HTTPS."
  type        = string
}

variable "private_route_table_ids" {
  description = "Private route tables that receive the S3 prefix-list route (app + data tiers)."
  type        = list(string)
}

variable "interface_subnet_ids" {
  description = "Subnets for interface endpoint ENIs (typically private app subnets per AZ)."
  type        = list(string)
}
