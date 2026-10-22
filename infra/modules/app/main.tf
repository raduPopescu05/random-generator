terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Latest Amazon Linux 2023 (ships with AWS CLI and the SSM agent).
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# HTTP in from the ALB only (rule added in the root module); no SSH, access via SSM.
resource "aws_security_group" "app" {
  name_prefix = "random-generator-app-"
  description = "HTTP only from the ALB"
  vpc_id      = var.VPC_ID
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_iam_role" "app" {
  name_prefix = "random-generator-"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ecr" {
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = var.ECR_REPOSITORY_ARNS
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "random-generator-"
  role        = aws_iam_role.app.name
}

locals {
  registry = split("/", var.BACKEND_IMAGE)[0]

  compose = yamlencode({
    services = {
      db = {
        image   = "mysql:8.4"
        restart = "unless-stopped"
        environment = {
          MYSQL_DATABASE      = var.DB_NAME
          MYSQL_USER          = var.DB_USER
          MYSQL_PASSWORD      = var.DB_PASSWORD
          MYSQL_ROOT_PASSWORD = var.DB_ROOT_PASSWORD
        }
        volumes = ["mysql-data:/var/lib/mysql"]
        healthcheck = {
          test         = ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -u root -p\"$$MYSQL_ROOT_PASSWORD\" --silent"]
          interval     = "5s"
          timeout      = "5s"
          retries      = 30
          start_period = "20s"
        }
      }
      api = {
        image   = var.BACKEND_IMAGE
        restart = "unless-stopped"
        environment = {
          DB_HOST     = "db"
          DB_PORT     = "3306"
          DB_NAME     = var.DB_NAME
          DB_USER     = var.DB_USER
          DB_PASSWORD = var.DB_PASSWORD
        }
        depends_on = { db = { condition = "service_healthy" } }
      }
      web = {
        image      = var.FRONTEND_IMAGE
        restart    = "unless-stopped"
        ports      = ["80:80"]
        depends_on = ["api"]
      }
    }
    volumes = { "mysql-data" = {} }
  })

  user_data = <<-EOT
    #!/bin/bash
    exec > >(tee /var/log/app-bootstrap.log) 2>&1
    set -x
    dnf install -y docker
    systemctl enable --now docker
    mkdir -p /usr/local/lib/docker/cli-plugins /opt/app
    curl -fsSL https://github.com/docker/compose/releases/download/v2.40.3/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    cat > /opt/app/docker-compose.yml <<'COMPOSE'
    ${local.compose}
    COMPOSE
    cd /opt/app
    # Images may be pushed to ECR after the instance boots, so retry until they exist.
    for i in $(seq 1 60); do
      aws ecr get-login-password --region ${var.REGION} | docker login --username AWS --password-stdin ${local.registry} \
        && docker compose pull && docker compose up -d && break
      sleep 20
    done
  EOT
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.INSTANCE_TYPE
  subnet_id                   = var.PRIVATE_SUBNET_ID
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # containers/CLI may need IMDS
  }
  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }
  tags = { Name = "random-generator" }

  depends_on = [
    aws_iam_role_policy.ecr,
    aws_iam_role_policy_attachment.ssm,
    aws_vpc_security_group_egress_rule.outbound,
  ]
}
