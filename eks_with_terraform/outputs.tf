output "cluster_name" { value = module.eks.cluster_name }
output "region" { value = var.region }
output "vpc_id" { value = module.network.vpc_id }
output "public_subnet_ids" { value = module.network.public_subnet_ids }
output "private_subnet_ids" { value = module.network.private_subnet_ids }
output "controller_role_arn" { value = module.eks.controller_role_arn }
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# Non-secret handoff to deploy.py; no manual copying of generated AWS IDs.
output "deployment_config" {
  value = {
    cluster_name        = module.eks.cluster_name
    region              = var.region
    aws_profile         = var.aws_profile
    vpc_id              = module.network.vpc_id
    controller_role_arn = module.eks.controller_role_arn
    backend_image       = var.backend_image
    frontend_image      = var.frontend_image
  }
}
