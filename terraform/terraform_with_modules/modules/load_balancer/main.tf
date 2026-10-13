# Provider configuration is inherited from the calling root module.
terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ALB and EC2 rules are separate resources to avoid reference cycles.
resource "aws_security_group" "alb" {
  name_prefix = "random-generator-alb-"
  description = "Public HTTP and HTTPS entry point"
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

# Public endpoint across two availability zones.
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

# Redirect browsers to HTTPS, preserving the host, path, and query string.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      host        = "#{host}"
      path        = "/#{path}"
      query       = "#{query}"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# Development only: the private key is stored in Terraform state.
resource "tls_private_key" "app" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# The generated ALB hostname is known after ALB creation; no domain is required.
resource "tls_self_signed_cert" "app" {
  private_key_pem       = tls_private_key.app.private_key_pem
  dns_names             = [aws_lb.app.dns_name]
  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]

  subject {
    common_name = "random-generator.local"
  }
}

resource "aws_acm_certificate" "app" {
  private_key      = tls_private_key.app.private_key_pem
  certificate_body = tls_self_signed_cert.app.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.app.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
