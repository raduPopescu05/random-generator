# Repository bootstrap with independent local state.
module "ecr" {
  source = "./modules/ecr"

  providers = { aws = aws }

  ECR_DEV_X64_BACKEND      = var.ECR_DEV_X64_BACKEND
  ECR_DEV_X64_FRONTEND     = var.ECR_DEV_X64_FRONTEND
  ECR_PREPROD_X64_BACKEND  = var.ECR_PREPROD_X64_BACKEND
  ECR_PREPROD_X64_FRONTEND = var.ECR_PREPROD_X64_FRONTEND
}
