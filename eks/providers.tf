terraform {
  required_version = ">= 1.11.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
  }
}

# Local state; credentials come from the AWS CLI profile or environment.
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "random-generator-eks-poc", ManagedBy = "Terraform" }
  }
}
