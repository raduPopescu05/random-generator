output "dev_x64_backend_url" {
  description = "URL of the dev x64 backend repository."
  value       = aws_ecr_repository.dev_x64_backend.repository_url
}

output "dev_x64_backend_arn" {
  description = "ARN of the dev x64 backend repository."
  value       = aws_ecr_repository.dev_x64_backend.arn
}

output "dev_x64_frontend_url" {
  description = "URL of the dev x64 frontend repository."
  value       = aws_ecr_repository.dev_x64_frontend.repository_url
}

output "dev_x64_frontend_arn" {
  description = "ARN of the dev x64 frontend repository."
  value       = aws_ecr_repository.dev_x64_frontend.arn
}

output "preprod_x64_backend_url" {
  description = "URL of the preprod x64 backend repository."
  value       = aws_ecr_repository.preprod_x64_backend.repository_url
}

output "preprod_x64_backend_arn" {
  description = "ARN of the preprod x64 backend repository."
  value       = aws_ecr_repository.preprod_x64_backend.arn
}

output "preprod_x64_frontend_url" {
  description = "URL of the preprod x64 frontend repository."
  value       = aws_ecr_repository.preprod_x64_frontend.repository_url
}

output "preprod_x64_frontend_arn" {
  description = "ARN of the preprod x64 frontend repository."
  value       = aws_ecr_repository.preprod_x64_frontend.arn
}
