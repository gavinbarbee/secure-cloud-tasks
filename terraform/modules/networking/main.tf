# -----------------------------------------------------------------------------
# Networking: Internet access for public subnets + outbound-only internet for
# private subnets via NAT. IGW attachment is implicit on public route.
# -----------------------------------------------------------------------------

# Single-NAT mode: place NAT in the first public subnet (cost-conscious dev).
# HA mode: one NAT per AZ, each private subnet uses the NAT in its AZ.
resource "aws_eip" "nat" {
  count = var.nat_gateway_count

  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "this" {
  count = var.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = var.public_subnet_ids[count.index]

  tags = {
    Name = "${var.name_prefix}-nat-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = var.internet_gateway_id
  }

  tags = {
    Name = "${var.name_prefix}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_ids)

  subnet_id      = var.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public.id
}

# Private route tables: one table shared (single NAT) or one per AZ (HA NAT).
resource "aws_route_table" "private" {
  count = var.nat_gateway_count

  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name = "${var.name_prefix}-rt-private-${count.index + 1}"
  }
}

locals {
  # Subnets are ordered: all app subnets (one per AZ), then all data subnets (same AZ order).
  # Each AZ's private subnets should use that AZ's NAT when HA; single NAT uses table 0.
  private_subnet_rt_index = [
    for i in range(length(var.private_subnet_ids)) :
    var.nat_gateway_count > 1 ? i % var.nat_gateway_count : 0
  ]
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_ids)

  subnet_id      = var.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private[local.private_subnet_rt_index[count.index]].id
}
