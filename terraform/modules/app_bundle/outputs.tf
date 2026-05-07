output "bucket_id" {
  value = aws_s3_bucket.app.id
}

output "bucket_arn" {
  value = aws_s3_bucket.app.arn
}

output "object_arn" {
  value = aws_s3_object.app.arn
}

output "object_key" {
  value = aws_s3_object.app.key
}
