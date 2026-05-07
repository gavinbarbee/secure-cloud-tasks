# -----------------------------------------------------------------------------
# Application Load Balancer: internet-facing entry point in public subnets.
# For production, add an HTTPS listener + ACM certificate and redirect HTTP.
# -----------------------------------------------------------------------------

# ALB `name_prefix` must be <= 6 characters; AWS appends a random suffix.
locals {
  short = substr(replace(var.name_prefix, "_", "-"), 0, 6)
}

resource "aws_lb" "this" {
  name_prefix        = local.short
  load_balancer_type = "application"
  internal           = false
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name_prefix = local.short
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health"
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name = "${var.name_prefix}-tg-app"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = {
    Name = "${var.name_prefix}-listener-http"
  }
}
