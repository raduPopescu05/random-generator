module "network" {
  source = "./modules/network"
  name   = var.cluster_name
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.26.0"

  name               = var.cluster_name
  kubernetes_version = "1.35"
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.private_subnet_ids

  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["0.0.0.0/0"]
  authentication_mode          = "API"
  enable_irsa                  = true
  create_node_security_group   = false
  create_node_iam_role         = false

  access_entries = {
    administrator = {
      principal_arn = var.admin_principal_arn
      policy_associations = {
        administrator = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  fargate_profiles = {
    application = {
      selectors = [{ namespace = "random-generator" }]
    }
    system = {
      selectors = [{ namespace = "kube-system" }]
    }
  }

  # The module installs this addon after Fargate profiles exist.
  addons = {
    coredns = {
      before_compute       = false
      configuration_values = jsonencode({ computeType = "Fargate" })
    }
  }
}
