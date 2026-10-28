variable "region" {
  type    = string
  default = "eu-central-1"
}
variable "cluster_name" {
  type    = string
  default = "random-generator-poc"
}
variable "admin_principal_arn" {
  description = "IAM user or role ARN granted Kubernetes cluster administrator access (not an STS session ARN)."
  type        = string
}
variable "db_username" {
  type    = string
  default = "random_app"
}
variable "db_password" {
  description = "POC database administrator password, set in the ignored tf.vars file and used for the Kubernetes database Secret. Stored in local Terraform state."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.db_password) >= 16 && length(var.db_password) <= 41 && can(regex("^[A-Za-z0-9_-]+$", var.db_password))
    error_message = "Use 16–41 ASCII letters, numbers, underscores or hyphens."
  }
}
