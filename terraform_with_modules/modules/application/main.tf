# Provider configuration is inherited from the calling root module.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# No SSH or database ingress is configured on EC2.
resource "aws_security_group" "app" {
  name_prefix = "random-generator-app-"
  description = "HTTP only from the ALB; administration through SSM"
  vpc_id      = var.VPC_ID
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
  subnet_id                   = var.PRIVATE_SUBNET_ID
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
    aws_iam_role_policy.ecr,
    aws_iam_role_policy_attachment.ssm,
    aws_vpc_security_group_egress_rule.app_outbound
  ]
}
