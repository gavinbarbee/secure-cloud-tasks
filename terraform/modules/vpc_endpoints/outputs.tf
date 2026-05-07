output "s3_gateway_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

output "interface_endpoint_security_group_id" {
  value = aws_security_group.vpc_endpoints.id
}
