output "vpc_id" {
  value = aws_vpc.random-generator-vpc.id
}
output "public_subnet_ids" {
  value      = aws_subnet.public[*].id
  depends_on = [aws_route_table_association.public]
}
output "private_subnet_ids" {
  value      = aws_subnet.private[*].id
  depends_on = [aws_route_table_association.private]
}
