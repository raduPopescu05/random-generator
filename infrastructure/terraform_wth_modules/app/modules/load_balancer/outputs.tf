output "application_url" {
  description = "Public HTTP endpoint."
  value       = "http://${aws_lb.app.dns_name}"
}
output "target_group_arn" {
  description = "Target group for the root-level EC2 attachment."
  value       = aws_lb_target_group.app.arn
}
output "security_group_id" {
  description = "ALB security group for the root-level application rules."
  value       = aws_security_group.alb.id
}
