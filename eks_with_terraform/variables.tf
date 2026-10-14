variable "region" {
  type    = string
  default = "eu-central-1"
}
variable "cluster_name" {
  type    = string
  default = "random-generator-eks"
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,38}$", var.cluster_name))
    error_message = "Use a letter followed by up to 38 letters, digits, or hyphens."
  }
}
variable "kubernetes_version" {
  type    = string
  default = "1.35"
}
variable "admin_principal_arn" {
  description = "IAM user or role ARN for cluster administration; not an STS session ARN."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/.+$", var.admin_principal_arn))
    error_message = "Supply an IAM user or role ARN, not an assumed-role session ARN."
  }
}
variable "public_access_cidrs" {
  description = "Operator public IPv4 CIDRs allowed to reach the Kubernetes API, typically /32."
  type        = list(string)
  validation {
    condition     = length(var.public_access_cidrs) > 0 && alltrue([for cidr in var.public_access_cidrs : can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"])
    error_message = "Supply valid restricted IPv4 CIDRs; 0.0.0.0/0 is not allowed."
  }
}
variable "vpc_cidr" {
  type    = string
  default = "10.43.0.0/16"
}
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.43.1.0/24", "10.43.2.0/24"]
}
variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.43.10.0/24", "10.43.11.0/24"]
}

variable "aws_profile" {
  description = "Optional local AWS profile used by Terraform and the deployment script. Null uses the normal environment credential chain."
  type        = string
  default     = null
}

variable "backend_image" {
  description = "Existing linux/amd64 backend image URI, with a tag or digest."
  type        = string
  validation {
    condition     = can(regex("^[^\\s@]+(:[^\\s/:@]+|@sha256:[a-f0-9]{64})$", var.backend_image))
    error_message = "Supply a complete image URI with a tag or digest and no whitespace."
  }
}

variable "frontend_image" {
  description = "Existing linux/amd64 frontend image URI, with a tag or digest."
  type        = string
  validation {
    condition     = can(regex("^[^\\s@]+(:[^\\s/:@]+|@sha256:[a-f0-9]{64})$", var.frontend_image))
    error_message = "Supply a complete image URI with a tag or digest and no whitespace."
  }
}
