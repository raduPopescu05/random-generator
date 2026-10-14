# Independent local state; no access keys are stored in Terraform inputs.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "random-generator-eks", ManagedBy = "Terraform" }
  }
}
