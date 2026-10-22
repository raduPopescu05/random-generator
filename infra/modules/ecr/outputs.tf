output "repository_urls" {
  description = "Repository URL per image name."
  value       = { for name, repo in aws_ecr_repository.app : name => repo.repository_url }
}

output "repository_arns" {
  value = [for repo in aws_ecr_repository.app : repo.arn]
}
