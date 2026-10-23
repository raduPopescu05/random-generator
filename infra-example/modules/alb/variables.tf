variable "VPC_ID" {
  description = "The vpc id of the VPC where the ALB is deployed"
  type        = string
}

variable "PUBLIC_SUBNET_IDS" {
  description = "2 public subnets is 2 distinct availability zones"
  type        = list(string)
}