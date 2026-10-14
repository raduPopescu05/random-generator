output "cluster_name" { value = aws_eks_cluster.this.name }
output "controller_role_arn" {
  value      = aws_iam_role.controller.arn
  depends_on = [aws_iam_role_policy_attachment.controller]
}
