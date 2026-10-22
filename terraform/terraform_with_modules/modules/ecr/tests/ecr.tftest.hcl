mock_provider "aws" {}

variables {
  ECR_DEV_X64_BACKEND      = "dev/random-generator-repository/x64/backend"
  ECR_DEV_X64_FRONTEND     = "dev/random-generator-repository/x64/frontend"
  ECR_DEV_ARM_BACKEND      = "dev/random-generator-repository/arm/backend"
  ECR_DEV_ARM_FRONTEND     = "dev/random-generator-repository/arm/frontend"
  ECR_PREPROD_X64_BACKEND  = "preprod/random-generator-repository/x64/backend"
  ECR_PREPROD_X64_FRONTEND = "preprod/random-generator-repository/x64/frontend"
  ECR_PREPROD_ARM_BACKEND  = "preprod/random-generator-repository/arm/backend"
  ECR_PREPROD_ARM_FRONTEND = "preprod/random-generator-repository/arm/frontend"
}

run "repository_configuration" {
  command = plan
  assert {
    condition     = aws_ecr_repository.dev_x64_backend.name == "dev/random-generator-repository/x64/backend" && aws_ecr_repository.dev_x64_backend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.dev_x64_backend.force_delete == false
    error_message = "Unexpected configuration for dev_x64_backend."
  }
  assert {
    condition     = aws_ecr_repository.dev_x64_frontend.name == "dev/random-generator-repository/x64/frontend" && aws_ecr_repository.dev_x64_frontend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.dev_x64_frontend.force_delete == false
    error_message = "Unexpected configuration for dev_x64_frontend."
  }
  assert {
    condition     = aws_ecr_repository.dev_arm_backend.name == "dev/random-generator-repository/arm/backend" && aws_ecr_repository.dev_arm_backend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.dev_arm_backend.force_delete == false
    error_message = "Unexpected configuration for dev_arm_backend."
  }
  assert {
    condition     = aws_ecr_repository.dev_arm_frontend.name == "dev/random-generator-repository/arm/frontend" && aws_ecr_repository.dev_arm_frontend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.dev_arm_frontend.force_delete == false
    error_message = "Unexpected configuration for dev_arm_frontend."
  }
  assert {
    condition     = aws_ecr_repository.preprod_x64_backend.name == "preprod/random-generator-repository/x64/backend" && aws_ecr_repository.preprod_x64_backend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.preprod_x64_backend.force_delete == false
    error_message = "Unexpected configuration for preprod_x64_backend."
  }
  assert {
    condition     = aws_ecr_repository.preprod_x64_frontend.name == "preprod/random-generator-repository/x64/frontend" && aws_ecr_repository.preprod_x64_frontend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.preprod_x64_frontend.force_delete == false
    error_message = "Unexpected configuration for preprod_x64_frontend."
  }
  assert {
    condition     = aws_ecr_repository.preprod_arm_backend.name == "preprod/random-generator-repository/arm/backend" && aws_ecr_repository.preprod_arm_backend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.preprod_arm_backend.force_delete == false
    error_message = "Unexpected configuration for preprod_arm_backend."
  }
  assert {
    condition     = aws_ecr_repository.preprod_arm_frontend.name == "preprod/random-generator-repository/arm/frontend" && aws_ecr_repository.preprod_arm_frontend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.preprod_arm_frontend.force_delete == false
    error_message = "Unexpected configuration for preprod_arm_frontend."
  }
}

run "individual_override" {
  command = plan
  variables {
    ECR_DEV_ARM_BACKEND = "custom/arm/backend"
  }
  assert {
    condition     = aws_ecr_repository.dev_x64_backend.name == "dev/random-generator-repository/x64/backend" && aws_ecr_repository.dev_x64_backend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.dev_x64_backend.force_delete == false
    error_message = "Unexpected configuration for dev_x64_backend."
  }
  assert {
    condition     = aws_ecr_repository.dev_x64_frontend.name == "dev/random-generator-repository/x64/frontend" && aws_ecr_repository.dev_x64_frontend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.dev_x64_frontend.force_delete == false
    error_message = "Unexpected configuration for dev_x64_frontend."
  }
  assert {
    condition     = aws_ecr_repository.dev_arm_backend.name == "custom/arm/backend" && aws_ecr_repository.dev_arm_backend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.dev_arm_backend.force_delete == false
    error_message = "Unexpected configuration for dev_arm_backend."
  }
  assert {
    condition     = aws_ecr_repository.dev_arm_frontend.name == "dev/random-generator-repository/arm/frontend" && aws_ecr_repository.dev_arm_frontend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.dev_arm_frontend.force_delete == false
    error_message = "Unexpected configuration for dev_arm_frontend."
  }
  assert {
    condition     = aws_ecr_repository.preprod_x64_backend.name == "preprod/random-generator-repository/x64/backend" && aws_ecr_repository.preprod_x64_backend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.preprod_x64_backend.force_delete == false
    error_message = "Unexpected configuration for preprod_x64_backend."
  }
  assert {
    condition     = aws_ecr_repository.preprod_x64_frontend.name == "preprod/random-generator-repository/x64/frontend" && aws_ecr_repository.preprod_x64_frontend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.preprod_x64_frontend.force_delete == false
    error_message = "Unexpected configuration for preprod_x64_frontend."
  }
  assert {
    condition     = aws_ecr_repository.preprod_arm_backend.name == "preprod/random-generator-repository/arm/backend" && aws_ecr_repository.preprod_arm_backend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.preprod_arm_backend.force_delete == false
    error_message = "Unexpected configuration for preprod_arm_backend."
  }
  assert {
    condition     = aws_ecr_repository.preprod_arm_frontend.name == "preprod/random-generator-repository/arm/frontend" && aws_ecr_repository.preprod_arm_frontend.image_tag_mutability == "MUTABLE" && aws_ecr_repository.preprod_arm_frontend.force_delete == false
    error_message = "Unexpected configuration for preprod_arm_frontend."
  }
}

run "repository_outputs" {
  command = apply
  override_resource {
    target = aws_ecr_repository.dev_x64_backend
    values = {
      repository_url = "834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/x64/backend"
      arn            = "arn:aws:ecr:eu-central-1:834251003876:repository/dev/random-generator-repository/x64/backend"
    }
  }
  assert {
    condition     = output.dev_x64_backend_url == "834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/x64/backend" && output.dev_x64_backend_arn == "arn:aws:ecr:eu-central-1:834251003876:repository/dev/random-generator-repository/x64/backend"
    error_message = "Unexpected outputs for dev_x64_backend."
  }
  override_resource {
    target = aws_ecr_repository.dev_x64_frontend
    values = {
      repository_url = "834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/x64/frontend"
      arn            = "arn:aws:ecr:eu-central-1:834251003876:repository/dev/random-generator-repository/x64/frontend"
    }
  }
  assert {
    condition     = output.dev_x64_frontend_url == "834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/x64/frontend" && output.dev_x64_frontend_arn == "arn:aws:ecr:eu-central-1:834251003876:repository/dev/random-generator-repository/x64/frontend"
    error_message = "Unexpected outputs for dev_x64_frontend."
  }
  override_resource {
    target = aws_ecr_repository.dev_arm_backend
    values = {
      repository_url = "834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/arm/backend"
      arn            = "arn:aws:ecr:eu-central-1:834251003876:repository/dev/random-generator-repository/arm/backend"
    }
  }
  assert {
    condition     = output.dev_arm_backend_url == "834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/arm/backend" && output.dev_arm_backend_arn == "arn:aws:ecr:eu-central-1:834251003876:repository/dev/random-generator-repository/arm/backend"
    error_message = "Unexpected outputs for dev_arm_backend."
  }
  override_resource {
    target = aws_ecr_repository.dev_arm_frontend
    values = {
      repository_url = "834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/arm/frontend"
      arn            = "arn:aws:ecr:eu-central-1:834251003876:repository/dev/random-generator-repository/arm/frontend"
    }
  }
  assert {
    condition     = output.dev_arm_frontend_url == "834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/arm/frontend" && output.dev_arm_frontend_arn == "arn:aws:ecr:eu-central-1:834251003876:repository/dev/random-generator-repository/arm/frontend"
    error_message = "Unexpected outputs for dev_arm_frontend."
  }
  override_resource {
    target = aws_ecr_repository.preprod_x64_backend
    values = {
      repository_url = "834251003876.dkr.ecr.eu-central-1.amazonaws.com/preprod/random-generator-repository/x64/backend"
      arn            = "arn:aws:ecr:eu-central-1:834251003876:repository/preprod/random-generator-repository/x64/backend"
    }
  }
  assert {
    condition     = output.preprod_x64_backend_url == "834251003876.dkr.ecr.eu-central-1.amazonaws.com/preprod/random-generator-repository/x64/backend" && output.preprod_x64_backend_arn == "arn:aws:ecr:eu-central-1:834251003876:repository/preprod/random-generator-repository/x64/backend"
    error_message = "Unexpected outputs for preprod_x64_backend."
  }
  override_resource {
    target = aws_ecr_repository.preprod_x64_frontend
    values = {
      repository_url = "834251003876.dkr.ecr.eu-central-1.amazonaws.com/preprod/random-generator-repository/x64/frontend"
      arn            = "arn:aws:ecr:eu-central-1:834251003876:repository/preprod/random-generator-repository/x64/frontend"
    }
  }
  assert {
    condition     = output.preprod_x64_frontend_url == "834251003876.dkr.ecr.eu-central-1.amazonaws.com/preprod/random-generator-repository/x64/frontend" && output.preprod_x64_frontend_arn == "arn:aws:ecr:eu-central-1:834251003876:repository/preprod/random-generator-repository/x64/frontend"
    error_message = "Unexpected outputs for preprod_x64_frontend."
  }
  override_resource {
    target = aws_ecr_repository.preprod_arm_backend
    values = {
      repository_url = "834251003876.dkr.ecr.eu-central-1.amazonaws.com/preprod/random-generator-repository/arm/backend"
      arn            = "arn:aws:ecr:eu-central-1:834251003876:repository/preprod/random-generator-repository/arm/backend"
    }
  }
  assert {
    condition     = output.preprod_arm_backend_url == "834251003876.dkr.ecr.eu-central-1.amazonaws.com/preprod/random-generator-repository/arm/backend" && output.preprod_arm_backend_arn == "arn:aws:ecr:eu-central-1:834251003876:repository/preprod/random-generator-repository/arm/backend"
    error_message = "Unexpected outputs for preprod_arm_backend."
  }
  override_resource {
    target = aws_ecr_repository.preprod_arm_frontend
    values = {
      repository_url = "834251003876.dkr.ecr.eu-central-1.amazonaws.com/preprod/random-generator-repository/arm/frontend"
      arn            = "arn:aws:ecr:eu-central-1:834251003876:repository/preprod/random-generator-repository/arm/frontend"
    }
  }
  assert {
    condition     = output.preprod_arm_frontend_url == "834251003876.dkr.ecr.eu-central-1.amazonaws.com/preprod/random-generator-repository/arm/frontend" && output.preprod_arm_frontend_arn == "arn:aws:ecr:eu-central-1:834251003876:repository/preprod/random-generator-repository/arm/frontend"
    error_message = "Unexpected outputs for preprod_arm_frontend."
  }
}
