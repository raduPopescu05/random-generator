variable "cluster_name" { type = string }
variable "vpc_cidr" { type = string }
variable "public_subnet_cidrs" {
  type = list(string)
  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Supply two public subnet CIDRs."
  }
}
variable "private_subnet_cidrs" {
  type = list(string)
  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Supply two private subnet CIDRs."
  }
}
