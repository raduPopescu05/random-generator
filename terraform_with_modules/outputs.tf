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
