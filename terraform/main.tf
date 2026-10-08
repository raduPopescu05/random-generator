# All infrastructure and bootstrap configuration is kept in this file.
# No backend block: state stays in terraform.tfstate on this computer.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "REGION" {
  type    = string
  default = "eu-central-1"
}

# Null credentials allow the standard AWS environment/profile chain as well.
variable "AWS_ACCESS_KEY_ID" {
  type      = string
  default   = null
  sensitive = true
}
variable "AWS_SECRET_ACCESS_KEY" {
  type      = string
  default   = null
  sensitive = true
}

# Supply the manually prepared AMI in tf.vars; there is no stock-image fallback.
variable "AMI_ID" {
  description = "Custom Ubuntu x86-64 AMI in REGION with the documented application setup."
  type        = string
}

variable "INSTANCE_TYPE" {
  description = "Choose an x86-64 instance with sufficient memory for MySQL and the API."
  type        = string
  default     = "t3.small"
}
variable "DISK_SIZE_GB" {
  type    = number
  default = 30
}
variable "VPC_CIDR" {
  type    = string
  default = "10.42.0.0/16"
}
variable "PUBLIC_SUBNET_CIDRS" {
  type    = list(string)
  default = ["10.42.1.0/24", "10.42.2.0/24"]
  validation {
    condition     = length(var.PUBLIC_SUBNET_CIDRS) == 2
    error_message = "Exactly two public subnet CIDRs are required."
  }
}
variable "PRIVATE_SUBNET_CIDR" {
  type    = string
  default = "10.42.10.0/24"
}
variable "DB_NAME" {
  type    = string
  default = "random_generator"
}
variable "DB_USER" {
  type    = string
  default = "random_app"
}
variable "DB_PASSWORD" {
  type      = string
  sensitive = true
}
variable "DB_ROOT_PASSWORD" {
  type      = string
  sensitive = true
}
variable "BACKEND_IMAGE" {
  description = "Private ECR URI in REGION, including tag or digest."
  type        = string
}
variable "FRONTEND_IMAGE" {
  description = "Private ECR URI in REGION, including tag or digest."
  type        = string
}

# Credentials are used by Terraform locally, never passed to EC2.
provider "aws" {
  region     = var.REGION
  access_key = var.AWS_ACCESS_KEY_ID
  secret_key = var.AWS_SECRET_ACCESS_KEY
  default_tags {
    tags = { Project = "Radu-random-generator", ManagedBy = "Terraform" }
  }
}

# Discover two standard availability zones in the requested region.
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

# The VPC contains the public ALB/NAT and private application server.
resource "aws_vpc" "app" {
  cidr_block           = var.VPC_CIDR
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "random-generator" }
}

# The ALB requires public subnets in two different availability zones.
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.app.id
  cidr_block        = var.PUBLIC_SUBNET_CIDRS[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "random-generator-public-${count.index + 1}" }
}

# The application has no public IP and runs in the first availability zone.
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = var.PRIVATE_SUBNET_CIDR
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "random-generator-private" }
}

# Internet access for the ALB and the NAT gateway.
resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
}

# Public subnet default route.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app.id
  }
}

# Apply the public routes to both ALB subnets.
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Stable outbound address for the NAT gateway, not for EC2.
resource "aws_eip" "nat" {
  domain = "vpc"
}

# One NAT gateway provides private outbound internet access for this example.
resource "aws_nat_gateway" "app" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.app, aws_route_table_association.public]
}

# EC2 reaches ECR, Docker Hub, Ubuntu, and Systems Manager through NAT.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.app.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.app.id
  }
}

# Apply the NAT route to the private subnet.
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ALB and EC2 rules are separate resources to avoid reference cycles.
resource "aws_security_group" "alb" {
  name_prefix = "random-generator-alb-"
  description = "Public HTTP entry point"
  vpc_id      = aws_vpc.app.id
}

# No SSH or database ingress is configured on EC2.
resource "aws_security_group" "app" {
  name_prefix = "random-generator-app-"
  description = "HTTP only from the ALB; administration through SSM"
  vpc_id      = aws_vpc.app.id
}

# Accept HTTP from browsers.
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# The ALB can forward only HTTP to the application security group.
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# Only the ALB can connect to EC2's published frontend port.
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# Outbound connectivity is required for bootstrap, registry pulls, and SSM.
resource "aws_vpc_security_group_egress_rule" "app_outbound" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# EC2 assumes this role instead of receiving static AWS keys.
resource "aws_iam_role" "app" {
  name_prefix = "random-generator-"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

# Allow Session Manager connections without inbound SSH.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Registry login is global; layer/image reads are limited to the supplied repositories.
resource "aws_iam_role_policy" "ecr" {
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = local.repository_arns
      }
    ]
  })
}

# Attach the IAM role to EC2.
resource "aws_iam_instance_profile" "app" {
  name_prefix = "random-generator-"
  role        = aws_iam_role.app.name
}

locals {
  images = [var.BACKEND_IMAGE, var.FRONTEND_IMAGE]
  repository_arns = distinct([for image in local.images :
    "arn:aws:ecr:${var.REGION}:${split(".", image)[0]}:repository/${split(":", split("@", join("/", slice(split("/", image), 1, length(split("/", image)))))[0])[0]}"
  ])

  # Shell-quoted assignments, sourced by the AMI helper (not a Compose dotenv file).
  runtime_values = {
    AWS_REGION       = var.REGION
    BACKEND_IMAGE    = var.BACKEND_IMAGE
    FRONTEND_IMAGE   = var.FRONTEND_IMAGE
    DB_NAME          = var.DB_NAME
    DB_USER          = var.DB_USER
    DB_PASSWORD      = var.DB_PASSWORD
    DB_ROOT_PASSWORD = var.DB_ROOT_PASSWORD
  }
  runtime_env = join("\n", [for key, value in local.runtime_values :
    "${key}='${replace(value, "'", "'\"'\"'")}'"
  ])

  # The AMI supplies all software, Compose/Nginx files, helpers, and the service.
  cloud_config = "#cloud-config\n${yamlencode({
    write_files = [{
      path        = "/opt/random-generator/runtime.env"
      content     = base64encode("${local.runtime_env}\n")
      encoding    = "b64"
      owner       = "root:root"
      permissions = "0600"
    }]
    runcmd = [["/opt/random-generator/start-app.sh"]]
  })}"
}

# Private server; replacement intentionally deletes its database/root disk.
resource "aws_instance" "app" {
  ami                         = var.AMI_ID
  instance_type               = var.INSTANCE_TYPE
  subnet_id                   = aws_subnet.private.id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  user_data_base64            = base64gzip(local.cloud_config)
  user_data_replace_on_change = true
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.DISK_SIZE_GB
    encrypted             = true
    delete_on_termination = true
  }
  tags = { Name = "random-generator" }
  depends_on = [
    aws_route_table_association.private,
    aws_iam_role_policy.ecr,
    aws_iam_role_policy_attachment.ssm,
    aws_vpc_security_group_egress_rule.app_outbound
  ]
}

# Public HTTP endpoint across two availability zones.
resource "aws_lb" "app" {
  name_prefix        = "rg-"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
  depends_on         = [aws_route_table_association.public]
}

# Health checks traverse Nginx, the backend, and the MySQL connection.
resource "aws_lb_target_group" "app" {
  name_prefix = "rg-"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.app.id
  health_check {
    path                = "/health/ready"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Register the only application server with the ALB.
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = 80
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

output "application_url" {
  value = "http://${aws_lb.app.dns_name}"
}
output "instance_id" {
  value = aws_instance.app.id
}
output "session_manager_command" {
  value = "aws ssm start-session --region ${var.REGION} --target ${aws_instance.app.id}"
}
