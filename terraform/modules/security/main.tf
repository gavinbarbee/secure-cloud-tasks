# -----------------------------------------------------------------------------
# Security: Security Groups (stateful, primary enforcement) + Network ACLs
# (stateless, subnet-level defense in depth). SGs follow least privilege; NACLs
# are intentionally more restrictive than "allow all private" to show design.
# -----------------------------------------------------------------------------

# --- Security Groups (instance / ENI level) ---
# Inline ingress/egress so Terraform replaces the default "allow all egress" on new SGs.

resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "ALB: HTTP/HTTPS from the internet only."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet (add ACM + TLS listener in production)."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS for future ACM listener."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Use VPC CIDR (not app SG) to avoid a create-time dependency cycle between ALB and app SGs.
  egress {
    description = "Forward to app tier inside the VPC."
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.name_prefix}-sg-alb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "app" {
  name_prefix = "${var.name_prefix}-app-"
  description = "App tier: only ALB may reach Gunicorn; DB and AWS APIs egress only."
  vpc_id      = var.vpc_id

  ingress {
    description     = "Gunicorn from ALB ENIs only."
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description     = "PostgreSQL to RDS only."
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.database.id]
  }

  egress {
    description = "HTTPS for AWS APIs (S3 artifact, Secrets Manager; prefer VPC endpoints in prod)."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-sg-app"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "database" {
  name_prefix = "${var.name_prefix}-db-"
  description = "RDS: PostgreSQL from app tier only."
  vpc_id      = var.vpc_id

  # CIDR-based ingress (not app SG) avoids a Terraform dependency cycle: app egress -> db SG,
  # db ingress -> app SG. Subnets here are dedicated to the app tier in this design.
  ingress {
    description = "PostgreSQL from private application subnets only."
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  egress {
    description = "HTTPS for RDS maintenance / AWS telemetry."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-sg-database"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Network ACLs (subnet level, stateless) ---

resource "aws_network_acl" "public" {
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  tags = {
    Name = "${var.name_prefix}-nacl-public"
  }
}

resource "aws_network_acl_rule" "public_in_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_in_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_in_ephemeral" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "public_out_vpc" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
}

resource "aws_network_acl_rule" "public_out_ephemeral_internet" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl" "private_app" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_app_subnet_ids

  tags = {
    Name = "${var.name_prefix}-nacl-private-app"
  }
}

resource "aws_network_acl_rule" "app_in_from_alb_subnets" {
  count = length(var.public_subnet_cidrs)

  network_acl_id = aws_network_acl.private_app.id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_cidrs[count.index]
  from_port      = var.app_port
  to_port        = var.app_port
}

# Return traffic for outbound internet/NAT/S3 connections uses public source IPs (not the VPC CIDR).
# Without this rule, HTTPS to S3/NAT can SYN but responses are dropped by the NACL (classic stateless pitfall).
resource "aws_network_acl_rule" "app_in_ephemeral_internet_return" {
  network_acl_id = aws_network_acl.private_app.id
  rule_number    = 190
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "app_in_ephemeral_internal" {
  network_acl_id = aws_network_acl.private_app.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "app_out_to_data" {
  count = length(var.private_data_subnet_cidrs)

  network_acl_id = aws_network_acl.private_app.id
  rule_number    = 100 + count.index
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_data_subnet_cidrs[count.index]
  from_port      = 5432
  to_port        = 5432
}

resource "aws_network_acl_rule" "app_out_https" {
  network_acl_id = aws_network_acl.private_app.id
  rule_number    = 200
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "app_out_ephemeral_nat" {
  network_acl_id = aws_network_acl.private_app.id
  rule_number    = 210
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl" "private_data" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_data_subnet_ids

  tags = {
    Name = "${var.name_prefix}-nacl-private-data"
  }
}

resource "aws_network_acl_rule" "data_in_pg_from_app" {
  count = length(var.private_app_subnet_cidrs)

  network_acl_id = aws_network_acl.private_data.id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_app_subnet_cidrs[count.index]
  from_port      = 5432
  to_port        = 5432
}

resource "aws_network_acl_rule" "data_in_ephemeral_from_app" {
  count = length(var.private_app_subnet_cidrs)

  network_acl_id = aws_network_acl.private_data.id
  rule_number    = 150 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_app_subnet_cidrs[count.index]
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "data_out_ephemeral_to_app" {
  count = length(var.private_app_subnet_cidrs)

  network_acl_id = aws_network_acl.private_data.id
  rule_number    = 100 + count.index
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_app_subnet_cidrs[count.index]
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "data_out_https" {
  network_acl_id = aws_network_acl.private_data.id
  rule_number    = 200
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}
