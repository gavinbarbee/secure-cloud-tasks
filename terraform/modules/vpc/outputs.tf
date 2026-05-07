output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}

output "availability_zones" {
  value = local.azs
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  value = aws_subnet.public[*].cidr_block
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_app_subnet_cidrs" {
  value = aws_subnet.private_app[*].cidr_block
}

output "private_data_subnet_ids" {
  value = aws_subnet.private_data[*].id
}

output "private_data_subnet_cidrs" {
  value = aws_subnet.private_data[*].cidr_block
}
