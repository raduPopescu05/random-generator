terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# One private repository per image; force_delete lets terraform destroy remove pushed images.
resource "aws_ecr_repository" "app" {
  for_each             = toset(["backend", "frontend"])
  name                 = "random-generator/${each.key}"
  force_delete         = true
  image_tag_mutability = "MUTABLE"
}
