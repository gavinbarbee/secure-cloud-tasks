# -----------------------------------------------------------------------------
# App bundle: zip the Flask app and upload to a private S3 bucket for EC2 bootstrap.
# Separated from compute so IAM can reference ARNs without a module cycle.
# -----------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 2
}

resource "aws_s3_bucket" "app" {
  bucket = "${var.name_prefix}-app-${random_id.suffix.hex}"

  tags = {
    Name = "${var.name_prefix}-app-artifacts"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "app_zip" {
  type        = "zip"
  source_dir  = var.app_source_dir
  output_path = "${path.module}/.build/app.zip"
}

resource "aws_s3_object" "app" {
  bucket       = aws_s3_bucket.app.id
  key          = "releases/app.zip"
  source       = data.archive_file.app_zip.output_path
  etag         = data.archive_file.app_zip.output_md5
  content_type = "application/zip"

  tags = {
    Name = "${var.name_prefix}-app-zip"
  }
}
