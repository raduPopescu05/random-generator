output "application_url" {
  description = "Public HTTP application URL."
  value       = module.load_balancer.application_url
}
output "instance_id" {
  description = "Private EC2 instance ID."
  value       = module.application.instance_id
}
output "session_manager_command" {
  description = "Run locally with an authenticated AWS CLI and the Session Manager plugin."
  value       = "aws ssm start-session --region ${var.REGION} --target ${module.application.instance_id}"
}

output "ecr_dev_x64_backend_url" {
  description = "URL of the dev x64 backend repository."
  value       = module.ecr.dev_x64_backend_url
}

output "ecr_dev_x64_backend_arn" {
  description = "ARN of the dev x64 backend repository."
  value       = module.ecr.dev_x64_backend_arn
}

output "ecr_dev_x64_frontend_url" {
  description = "URL of the dev x64 frontend repository."
  value       = module.ecr.dev_x64_frontend_url
}

output "ecr_dev_x64_frontend_arn" {
  description = "ARN of the dev x64 frontend repository."
  value       = module.ecr.dev_x64_frontend_arn
}

output "ecr_dev_arm_backend_url" {
  description = "URL of the dev arm backend repository."
  value       = module.ecr.dev_arm_backend_url
}

output "ecr_dev_arm_backend_arn" {
  description = "ARN of the dev arm backend repository."
  value       = module.ecr.dev_arm_backend_arn
}

output "ecr_dev_arm_frontend_url" {
  description = "URL of the dev arm frontend repository."
  value       = module.ecr.dev_arm_frontend_url
}

output "ecr_dev_arm_frontend_arn" {
  description = "ARN of the dev arm frontend repository."
  value       = module.ecr.dev_arm_frontend_arn
}

output "ecr_preprod_x64_backend_url" {
  description = "URL of the preprod x64 backend repository."
  value       = module.ecr.preprod_x64_backend_url
}

output "ecr_preprod_x64_backend_arn" {
  description = "ARN of the preprod x64 backend repository."
  value       = module.ecr.preprod_x64_backend_arn
}

output "ecr_preprod_x64_frontend_url" {
  description = "URL of the preprod x64 frontend repository."
  value       = module.ecr.preprod_x64_frontend_url
}

output "ecr_preprod_x64_frontend_arn" {
  description = "ARN of the preprod x64 frontend repository."
  value       = module.ecr.preprod_x64_frontend_arn
}

output "ecr_preprod_arm_backend_url" {
  description = "URL of the preprod arm backend repository."
  value       = module.ecr.preprod_arm_backend_url
}

output "ecr_preprod_arm_backend_arn" {
  description = "ARN of the preprod arm backend repository."
  value       = module.ecr.preprod_arm_backend_arn
}

output "ecr_preprod_arm_frontend_url" {
  description = "URL of the preprod arm frontend repository."
  value       = module.ecr.preprod_arm_frontend_url
}

output "ecr_preprod_arm_frontend_arn" {
  description = "ARN of the preprod arm frontend repository."
  value       = module.ecr.preprod_arm_frontend_arn
}
