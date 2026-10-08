variable "VPC_ID" {
  description = "VPC in which to create the application security group."
  type        = string
}
variable "PRIVATE_SUBNET_ID" {
  description = "Private subnet with working outbound routing."
  type        = string
}
variable "REGION" {
  type    = string
  default = "eu-central-1"
}

# Supply the manually prepared AMI in tf.vars; there is no stock-image fallback.
variable "AMI_ID" {
  description = "Custom Ubuntu x86-64 AMI in REGION with the documented application setup."
  type        = string
}

variable "INSTANCE_TYPE" {
  description = "Choose an x86-64 instance with sufficient memory for MySQL and the API."
  type        = string
  default     = "t3.small"
}

variable "DISK_SIZE_GB" {
  type    = number
  default = 30
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

variable "BACKEND_IMAGE" {
  description = "Private ECR URI in REGION, including tag or digest."
  type        = string
}

variable "FRONTEND_IMAGE" {
  description = "Private ECR URI in REGION, including tag or digest."
  type        = string
}
