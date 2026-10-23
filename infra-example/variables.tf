variable "REGION_EU_CENTRAL_1" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "eu-central-1"
}

variable "REGION_US_EAST_1" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
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

