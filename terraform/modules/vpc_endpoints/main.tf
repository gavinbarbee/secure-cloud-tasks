# -----------------------------------------------------------------------------
# VPC endpoints: keep private instances off the public internet for AWS APIs and
# S3 (repos + artifacts). Gateway endpoint for S3; interface endpoints for APIs
# used at boot (Secrets Manager) and for operator access (SSM / EC2 messages).
#
# S3 gateway endpoint policy: must be set explicitly. Omitting `policy` in Terraform
# does not remove an existing policy on the endpoint (403s persist). AWS default is
# effectively allow-all-S3 for callers that also pass IAM; we mirror that here.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "s3_gateway_full_access" {
  statement {
    sid       = "AllowAllS3ViaGateway"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

locals {
  interface_services = {
    ssm            = "com.amazonaws.${var.aws_region}.ssm"
    ssmmessages    = "com.amazonaws.${var.aws_region}.ssmmessages"
    ec2messages    = "com.amazonaws.${var.aws_region}.ec2messages"
    secretsmanager = "com.amazonaws.${var.aws_region}.secretsmanager"
    ec2            = "com.amazonaws.${var.aws_region}.ec2"
    sts            = "com.amazonaws.${var.aws_region}.sts"
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.name_prefix}-vpce-"
  description = "HTTPS from VPC to interface VPC endpoints (SSM, Secrets Manager, EC2, etc.)."
  vpc_id      = var.vpc_id

  ingress {
    description = "TLS from workloads in the VPC to AWS API VPC endpoints."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Return traffic to clients (stateful SG; kept explicit for reviews)."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-sg-vpc-endpoints"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# S3: gateway endpoint + routes in private route tables (no NAT required for S3).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids
  policy            = data.aws_iam_policy_document.s3_gateway_full_access.json

  tags = {
    Name = "${var.name_prefix}-vpce-s3-gateway"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_services

  vpc_id              = var.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.interface_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name_prefix}-vpce-${each.key}"
  }
}
