terraform {
  required_version = ">= 1.11.0, < 2.0.0"
  backend "s3" {
    bucket       = "random-generator-tfstate-378149659384"
    key          = "infra/terraform.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
