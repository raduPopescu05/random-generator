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

variable "VPC_CIDR" {
  type    = string
  default = "10.42.0.0/16"
}

variable "PUBLIC_SUBNET_CIDRS" {
  type    = list(string)
  default = ["10.42.1.0/24", "10.42.2.0/24"]
  validation {
    condition     = length(var.PUBLIC_SUBNET_CIDRS) == 2
    error_message = "Exactly two public subnet CIDRs are required."
  }
}

variable "PRIVATE_SUBNET_CIDR" {
  type    = string
  default = "10.42.10.0/24"
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
