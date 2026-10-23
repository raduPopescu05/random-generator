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
