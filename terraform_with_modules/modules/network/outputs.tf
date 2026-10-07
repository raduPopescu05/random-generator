output "vpc_id" {
  description = "VPC for the application and ALB."
  value       = aws_vpc.app.id
}
output "public_subnet_ids" {
  description = "Public subnets ready for ALB use."
  value       = aws_subnet.public[*].id
  depends_on  = [aws_route_table_association.public]
}
output "private_subnet_id" {
  description = "Private subnet with NAT routing ready before EC2 boot."
  value       = aws_subnet.private.id
  depends_on  = [aws_route_table_association.private]
}
