variable "REGION" {
  type    = string
  default = "eu-central-1"
}

# Null credentials allow the standard AWS environment/profile chain as well.
variable "AWS_ACCESS_KEY_ID" {
  type      = string
  default   = null
  sensitive = true
}

variable "AWS_SECRET_ACCESS_KEY" {
  type      = string
  default   = null
  sensitive = true
}

variable "ECR_DEV_X64_BACKEND" {
  description = "ECR repository name for dev x64 backend."
  type        = string
}

variable "ECR_DEV_X64_FRONTEND" {
  description = "ECR repository name for dev x64 frontend."
  type        = string
}

variable "ECR_DEV_ARM_BACKEND" {
  description = "ECR repository name for dev arm backend."
  type        = string
}

variable "ECR_DEV_ARM_FRONTEND" {
  description = "ECR repository name for dev arm frontend."
  type        = string
}

variable "ECR_PREPROD_X64_BACKEND" {
  description = "ECR repository name for preprod x64 backend."
  type        = string
}

variable "ECR_PREPROD_X64_FRONTEND" {
  description = "ECR repository name for preprod x64 frontend."
  type        = string
}

variable "ECR_PREPROD_ARM_BACKEND" {
  description = "ECR repository name for preprod arm backend."
  type        = string
}

variable "ECR_PREPROD_ARM_FRONTEND" {
  description = "ECR repository name for preprod arm frontend."
  type        = string
}
