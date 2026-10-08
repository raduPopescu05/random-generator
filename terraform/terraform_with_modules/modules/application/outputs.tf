output "instance_id" {
  description = "EC2 target for the ALB and Session Manager."
  value       = aws_instance.app.id
}
output "security_group_id" {
  description = "Application security group for root-level ALB rules."
  value       = aws_security_group.app.id
}
