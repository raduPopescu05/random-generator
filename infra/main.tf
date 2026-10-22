provider "aws" {
  region = var.REGION_EU_CENTRAL_1
  default_tags {
    tags = { Project = "random-generator", ManagedBy = "Terraform" }
  }
}

module "network_eu_central_1" {
  source = "./modules/network"

  VPC_CIDR            = var.VPC_CIDR
  PUBLIC_SUBNET_CIDRS = var.PUBLIC_SUBNET_CIDRS
  PRIVATE_SUBNET_CIDR = var.PRIVATE_SUBNET_CIDR
  REGION              = var.REGION_EU_CENTRAL_1
}

module "ecr_eu_central_1" {
  source = "./modules/ecr"
}

module "alb_eu_central_1" {
  source = "./modules/alb"

  VPC_ID            = module.network_eu_central_1.vpc_id
  PUBLIC_SUBNET_IDS = module.network_eu_central_1.public_subnet_ids
}

module "app_eu_central_1" {
  source = "./modules/app"

  VPC_ID              = module.network_eu_central_1.vpc_id
  PRIVATE_SUBNET_ID   = module.network_eu_central_1.private_subnet_id
  REGION              = var.REGION_EU_CENTRAL_1
  INSTANCE_TYPE       = var.INSTANCE_TYPE
  BACKEND_IMAGE       = "${module.ecr_eu_central_1.repository_urls["backend"]}:${var.IMAGE_TAG}"
  FRONTEND_IMAGE      = "${module.ecr_eu_central_1.repository_urls["frontend"]}:${var.IMAGE_TAG}"
  ECR_REPOSITORY_ARNS = module.ecr_eu_central_1.repository_arns
  DB_PASSWORD         = var.DB_PASSWORD
  DB_ROOT_PASSWORD    = var.DB_ROOT_PASSWORD
}

# The ALB may only forward HTTP to the application security group...
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = module.alb_eu_central_1.security_group_id
  referenced_security_group_id = module.app_eu_central_1.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# ...and the application accepts HTTP only from the ALB.
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id            = module.app_eu_central_1.security_group_id
  referenced_security_group_id = module.alb_eu_central_1.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = module.alb_eu_central_1.target_group_arn
  target_id        = module.app_eu_central_1.instance_id
  port             = 80
}
