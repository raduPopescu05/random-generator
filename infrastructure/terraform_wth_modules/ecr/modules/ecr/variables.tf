variable "ECR_DEV_X64_BACKEND" {
  description = "ECR repository name for dev x64 backend."
  type        = string
}

variable "ECR_DEV_X64_FRONTEND" {
  description = "ECR repository name for dev x64 frontend."
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
