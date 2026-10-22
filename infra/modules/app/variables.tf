variable "VPC_ID" {
  type = string
}

variable "PRIVATE_SUBNET_ID" {
  type = string
}

variable "REGION" {
  type = string
}

variable "INSTANCE_TYPE" {
  type    = string
  default = "t3.small"
}

variable "BACKEND_IMAGE" {
  description = "Full ECR URI of the backend image, with tag."
  type        = string
}

variable "FRONTEND_IMAGE" {
  description = "Full ECR URI of the frontend image, with tag."
  type        = string
}

variable "ECR_REPOSITORY_ARNS" {
  type = list(string)
}

variable "DB_NAME" {
  type    = string
  default = "random_generator"
}

variable "DB_USER" {
  type    = string
  default = "random_app"
}

variable "DB_PASSWORD" {
  type      = string
  sensitive = true
}

variable "DB_ROOT_PASSWORD" {
  type      = string
  sensitive = true
}
