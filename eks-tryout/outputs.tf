output "region" {
  value = var.region
}
output "cluster_name" {
  value = module.eks.cluster_name
}
output "vpc_id" {
  value = module.network.vpc_id
}
output "controller_role_arn" {
  value = aws_iam_role.controller.arn
}
output "db_host" {
  value = aws_db_instance.app.address
}
output "db_username" {
  value = var.db_username
}
