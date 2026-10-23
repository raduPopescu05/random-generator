variable "VPC_ID" {
  description = "VPC shared with the application."
  type        = string
}
variable "PUBLIC_SUBNET_IDS" {
  description = "Two public subnets in distinct availability zones with internet routing."
  type        = list(string)
}
