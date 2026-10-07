# Provider configuration is inherited from the calling root module.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ALB and EC2 rules are separate resources to avoid reference cycles.
resource "aws_security_group" "alb" {
  name_prefix = "random-generator-alb-"
  description = "Public HTTP entry point"
  vpc_id      = var.VPC_ID
}

# Accept HTTP from browsers.
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# Public HTTP endpoint across two availability zones.
resource "aws_lb" "app" {
  name_prefix        = "rg-"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.PUBLIC_SUBNET_IDS
  security_groups    = [aws_security_group.alb.id]
}

# Health checks traverse Nginx, the backend, and the MySQL connection.
resource "aws_lb_target_group" "app" {
  name_prefix = "rg-"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.VPC_ID
  health_check {
    path                = "/health/ready"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# HTTP-only listener for this example.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
