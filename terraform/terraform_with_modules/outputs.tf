output "application_url" {
  description = "Public HTTPS application URL using a self-signed development certificate."
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

output "certificate_pem" {
  description = "Public certificate for trusting this development ALB explicitly."
  value       = module.load_balancer.certificate_pem
}
