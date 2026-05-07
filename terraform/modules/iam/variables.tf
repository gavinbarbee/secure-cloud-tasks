variable "name_prefix" {
  type = string
}

variable "app_artifact_bucket_arn" {
  description = "S3 bucket ARN containing the zipped Flask application."
  type        = string
}

variable "app_artifact_object_arn" {
  description = "Full ARN of the zip object (for GetObject)."
  type        = string
}

variable "app_artifact_prefix" {
  description = "Prefix used in ListBucket condition (e.g. releases/)."
  type        = string
}

variable "database_secret_arn" {
  description = "Secrets Manager secret ARN holding DB connection JSON."
  type        = string
}

variable "attach_ssm_managed_policy" {
  description = "Attach AmazonSSMManagedInstanceCore for Session Manager shell access."
  type        = bool
  default     = true
}
