output "application_url" {
  description = "Public URL to give to the reviewer."
  value       = "http://${module.alb_eu_central_1.dns_name}"
}

output "ecr_repository_urls" {
  value = module.ecr_eu_central_1.repository_urls
}

output "instance_id" {
  value = module.app_eu_central_1.instance_id
}
