variable "name_prefix" {
  type = string
}

variable "app_source_dir" {
  description = "Absolute or root-relative path to the Flask app directory to zip."
  type        = string
}
