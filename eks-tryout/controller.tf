locals {
  oidc_issuer = trimprefix(module.eks.cluster_oidc_issuer_url, "https://")
}

data "aws_iam_policy_document" "controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = "${var.cluster_name}-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.controller_assume_role.json
}

# Official controller v2.14.1 policy, vendored for reproducible installation.
resource "aws_iam_policy" "controller" {
  name   = "${var.cluster_name}-load-balancer-controller"
  policy = file("${path.module}/iam/load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}
