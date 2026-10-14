module "network" {
  source               = "./modules/network"
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}
module "eks" {
  source              = "./modules/eks"
  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  private_subnet_ids  = module.network.private_subnet_ids
  public_access_cidrs = var.public_access_cidrs
  admin_principal_arn = var.admin_principal_arn
}
