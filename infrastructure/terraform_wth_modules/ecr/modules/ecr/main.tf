terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# All repositories use the AWS provider passed by the caller.
# The ECR root configures that provider with region = var.REGION.
resource "aws_ecr_repository" "dev_x64_backend" {
  name                 = var.ECR_DEV_X64_BACKEND
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

resource "aws_ecr_repository" "dev_x64_frontend" {
  name                 = var.ECR_DEV_X64_FRONTEND
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

resource "aws_ecr_repository" "dev_arm_backend" {
  name                 = var.ECR_DEV_ARM_BACKEND
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

resource "aws_ecr_repository" "dev_arm_frontend" {
  name                 = var.ECR_DEV_ARM_FRONTEND
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

resource "aws_ecr_repository" "preprod_x64_backend" {
  name                 = var.ECR_PREPROD_X64_BACKEND
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

resource "aws_ecr_repository" "preprod_x64_frontend" {
  name                 = var.ECR_PREPROD_X64_FRONTEND
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

resource "aws_ecr_repository" "preprod_arm_backend" {
  name                 = var.ECR_PREPROD_ARM_BACKEND
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

resource "aws_ecr_repository" "preprod_arm_frontend" {
  name                 = var.ECR_PREPROD_ARM_FRONTEND
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}
