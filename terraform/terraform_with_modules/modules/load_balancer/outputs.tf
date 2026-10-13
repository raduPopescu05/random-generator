output "application_url" {
  description = "Public HTTPS endpoint using a self-signed development certificate."
  value       = "https://${aws_lb.app.dns_name}"
}
output "target_group_arn" {
  description = "Target group for the root-level EC2 attachment."
  value       = aws_lb_target_group.app.arn
}
output "security_group_id" {
  description = "ALB security group for the root-level application rules."
  value       = aws_security_group.alb.id
}

output "certificate_pem" {
  description = "Public self-signed certificate for explicit client trust; contains no private key."
  value       = tls_self_signed_cert.app.cert_pem
}
