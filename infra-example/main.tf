provider "aws" {
  region = var.REGION_EU_CENTRAL_1
}

module "network_eu_central_1" {
  source = "./modules/network"

  VPC_CIDR            = var.VPC_CIDR
  PUBLIC_SUBNET_CIDRS = var.PUBLIC_SUBNET_CIDRS
  PRIVATE_SUBNET_CIDR = var.PRIVATE_SUBNET_CIDR
  REGION              = var.REGION_EU_CENTRAL_1
}


module "alb_eu_central_1" {
  source = "./modules/alb"

  VPC_ID            = module.network_eu_central_1.vpc_id
  PUBLIC_SUBNET_IDS = module.network_eu_central_1.public_subnet_ids

}

