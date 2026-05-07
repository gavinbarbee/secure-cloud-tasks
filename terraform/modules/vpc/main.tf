# -----------------------------------------------------------------------------
# VPC module: isolated network boundary + tiered subnets (public / app / data).
# Route tables and NAT live in the networking module. Private workloads use the
# separate vpc_endpoints module (S3 gateway + interface endpoints) so S3/SSM/
# Secrets Manager/EC2 APIs do not depend on a NAT path for bootstrap traffic.
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /24 subnets derived from the VPC CIDR (documented pattern for interviews).
  public_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 1)]
  app_cidrs    = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 10 + i + 1)]
  data_cidrs   = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 20 + i + 1)]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-${substr(local.azs[count.index], -1, 1)}"
    Tier = "public"
  }
}

resource "aws_subnet" "private_app" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.app_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.name_prefix}-private-app-${substr(local.azs[count.index], -1, 1)}"
    Tier = "private-app"
  }
}

resource "aws_subnet" "private_data" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.data_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.name_prefix}-private-data-${substr(local.azs[count.index], -1, 1)}"
    Tier = "private-data"
  }
}

# Optional: VPC Flow Logs to a dedicated log group (controlled by root variable).
resource "aws_cloudwatch_log_group" "vpc_flow" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name_prefix}-flow"
  retention_in_days = 7

  tags = {
    Name = "${var.name_prefix}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix = "${var.name_prefix}-flow-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix = "${var.name_prefix}-flow-"
  role        = aws_iam_role.vpc_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  iam_role_arn         = aws_iam_role.vpc_flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow[0].arn

  tags = {
    Name = "${var.name_prefix}-vpc-flow"
  }
}
