variable "name" {
  type = string
}
variable "vpc_cidr" {
  type    = string
  default = "10.60.0.0/16"
}
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.60.1.0/24", "10.60.2.0/24"]
  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Exactly two public subnet CIDRs are required."
  }
}
variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.60.10.0/24", "10.60.20.0/24"]
  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Exactly two private subnet CIDRs are required."
  }
}
