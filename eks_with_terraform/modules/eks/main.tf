terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version
  # Keep EKS's initial CoreDNS deployment; patch it for Fargate after applying.
  bootstrap_self_managed_addons = true
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }
  depends_on = [aws_iam_role_policy_attachment.cluster]
}
resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_principal_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}

resource "aws_iam_role" "fargate" {
  name = "${var.cluster_name}-fargate"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        ArnLike = { "aws:SourceArn" = "arn:aws:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:fargateprofile/${var.cluster_name}/*" }
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "fargate" {
  role       = aws_iam_role.fargate.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}
resource "aws_eks_fargate_profile" "application" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "application"
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.private_subnet_ids
  selector { namespace = "random-generator" }
  depends_on = [aws_iam_role_policy_attachment.fargate]
}
resource "aws_eks_fargate_profile" "system" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "system"
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = var.private_subnet_ids
  selector {
    namespace = "kube-system"
    labels    = { "k8s-app" = "kube-dns" }
  }
  selector {
    namespace = "kube-system"
    labels    = { "app.kubernetes.io/name" = "aws-load-balancer-controller" }
  }
  # EKS allows only one Fargate profile creation at a time per cluster.
  depends_on = [aws_eks_fargate_profile.application]
}

# IAM retrieves the provider's trusted CA thumbprint when none is supplied.
resource "aws_iam_openid_connect_provider" "cluster" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
locals {
  oidc_hostpath = replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")
}
resource "aws_iam_role" "controller" {
  name = "${var.cluster_name}-load-balancer-controller"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_hostpath}:aud" = "sts.amazonaws.com"
          "${local.oidc_hostpath}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}
resource "aws_iam_policy" "controller" {
  name   = "${var.cluster_name}-load-balancer-controller"
  policy = file("${path.module}/controller-iam-policy.json")
}
resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}
# Fargate pods and the EKS control plane share the EKS-created cluster security
# group. Its default self-ingress permits the controller's TCP 9443 webhook.
# Do not replace that default rule; the controller manages ALB-to-pod ingress.
