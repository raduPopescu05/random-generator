variable "cluster_name" { type = string }
variable "kubernetes_version" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "public_access_cidrs" { type = list(string) }
variable "admin_principal_arn" { type = string }
