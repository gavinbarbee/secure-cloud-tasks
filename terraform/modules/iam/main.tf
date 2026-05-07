# -----------------------------------------------------------------------------
# IAM: Least-privilege role for EC2 app instances (no long-lived keys on disk).
# Permissions: read app artifact from S3, read DB secret, minimal logging.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name_prefix        = "${var.name_prefix}-ec2-app-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name = "${var.name_prefix}-role-app-ec2"
  }
}

data "aws_iam_policy_document" "app_permissions" {
  statement {
    sid = "S3ReadArtifact"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    resources = [var.app_artifact_object_arn]
  }

  statement {
    sid = "S3ListBucketPrefix"
    actions = [
      "s3:ListBucket",
    ]
    resources = [var.app_artifact_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.app_artifact_prefix]
    }
  }

  statement {
    sid = "SecretsManagerReadDatabase"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [var.database_secret_arn]
  }
}

resource "aws_iam_role_policy" "app_inline" {
  name_prefix = "${var.name_prefix}-app-"
  role        = aws_iam_role.app.id
  policy      = data.aws_iam_policy_document.app_permissions.json
}

# Optional: attach AWS managed policy for SSM Session Manager (break-glass admin access).
resource "aws_iam_role_policy_attachment" "ssm_core" {
  count = var.attach_ssm_managed_policy ? 1 : 0

  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "${var.name_prefix}-app-"
  role        = aws_iam_role.app.name

  tags = {
    Name = "${var.name_prefix}-profile-app-ec2"
  }
}
