variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "internet_gateway_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Public subnets (NAT gateways are created here)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "All private subnets (app + data) that should default-route to NAT."
  type        = list(string)
}

variable "nat_gateway_count" {
  description = "1 for single NAT, or match AZ count for HA (one NAT per public subnet index)."
  type        = number
}
