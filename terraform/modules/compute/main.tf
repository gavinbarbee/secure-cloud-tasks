# -----------------------------------------------------------------------------
# Compute: single EC2 in a private app subnet, registered behind the ALB target
# group. User data installs the app bundle and wires Secrets Manager → env file.
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    region     = var.aws_region
    bucket     = var.app_artifact_bucket
    object_key = var.app_artifact_key
    secret_arn = var.database_secret_arn
    app_port   = var.app_port
  })
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.private_app_subnet_ids[0]
  vpc_security_group_ids = [var.app_security_group_id]
  iam_instance_profile   = var.iam_instance_profile_name

  user_data                   = base64encode(local.user_data)
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.name_prefix}-ec2-app"
  }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = var.alb_target_group_arn
  target_id        = aws_instance.app.id
  port             = var.app_port
}
