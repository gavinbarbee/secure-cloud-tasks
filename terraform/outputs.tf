output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer (open in browser)."
  value       = module.alb.alb_dns_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "database_secret_arn" {
  description = "Secrets Manager ARN holding DB connection JSON for operators / rotation."
  value       = aws_secretsmanager_secret.app_database.arn
  sensitive   = false
}

output "app_artifact_bucket" {
  description = "S3 bucket where the Flask bundle is uploaded during apply."
  value       = module.app_bundle.bucket_id
}

output "vpc_endpoint_s3_gateway_id" {
  description = "S3 gateway VPC endpoint (private route tables use the S3 prefix list)."
  value       = module.vpc_endpoints.s3_gateway_endpoint_id
}
