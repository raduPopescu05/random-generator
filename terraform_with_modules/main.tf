# Independent example with local state in this directory.
module "network" {
  source              = "./modules/network"
  VPC_CIDR            = var.VPC_CIDR
  PUBLIC_SUBNET_CIDRS = var.PUBLIC_SUBNET_CIDRS
  PRIVATE_SUBNET_CIDR = var.PRIVATE_SUBNET_CIDR
}

module "application" {
  source            = "./modules/application"
  VPC_ID            = module.network.vpc_id
  PRIVATE_SUBNET_ID = module.network.private_subnet_id
  REGION            = var.REGION
  AMI_ID            = var.AMI_ID
  INSTANCE_TYPE     = var.INSTANCE_TYPE
  DISK_SIZE_GB      = var.DISK_SIZE_GB
  DB_NAME           = var.DB_NAME
  DB_USER           = var.DB_USER
  DB_PASSWORD       = var.DB_PASSWORD
  DB_ROOT_PASSWORD  = var.DB_ROOT_PASSWORD
  BACKEND_IMAGE     = var.BACKEND_IMAGE
  FRONTEND_IMAGE    = var.FRONTEND_IMAGE
}

module "load_balancer" {
  source            = "./modules/load_balancer"
  VPC_ID            = module.network.vpc_id
  PUBLIC_SUBNET_IDS = module.network.public_subnet_ids
}

# The ALB can forward only HTTP to the application security group.
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = module.load_balancer.security_group_id
  referenced_security_group_id = module.application.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# Only the ALB can connect to EC2's published frontend port.
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id            = module.application.security_group_id
  referenced_security_group_id = module.load_balancer.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# Register the only application server with the ALB.
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = module.load_balancer.target_group_arn
  target_id        = module.application.instance_id
  port             = 80
}
