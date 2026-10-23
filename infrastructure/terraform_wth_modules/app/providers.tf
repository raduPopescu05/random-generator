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

# Credentials are used by Terraform locally, never passed to EC2.
provider "aws" {
  region     = var.REGION
  access_key = var.AWS_ACCESS_KEY_ID
  secret_key = var.AWS_SECRET_ACCESS_KEY
  default_tags {
    tags = { Project = "Radu-random-generator", ManagedBy = "Terraform" }
  }
}
