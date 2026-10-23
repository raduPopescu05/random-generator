# ECR repository bootstrap

This Terraform root creates only four private ECR repositories. Run it before
publishing images, then deploy the application with the published image URIs.
See the [ordered deployment guide](../README.md) for the complete workflow.

## Configuration and usage

Use Terraform >= 1.11 and < 2.0. From the repository root, for a fresh setup:

```sh
cd infrastructure/terraform_wth_modules/ecr
cp tf.vars.example tf.vars
terraform init
terraform validate
terraform plan -var-file=tf.vars -out=ecr.tfplan
terraform apply ecr.tfplan
```

Run the remaining Terraform commands from this ECR directory.

Review the plan before applying; do not overwrite existing local variable files.
`REGION` defaults to `eu-central-1`. The root provider uses `region = var.REGION`
and is explicitly passed to `module.ecr`. Credentials use the standard AWS
profile/environment chain, or the optional sensitive `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` inputs. Default tags match the application root.
No AMI, database credentials, or application image inputs are required.

The four required `ECR_*` inputs in `tf.vars.example` preserve existing names:
`{dev,preprod}/random-generator-repository/x64/{backend,frontend}`.
They must match the CI destinations; CI currently uses account `834251003876`
and region `eu-central-1`. Keep this root as their single Terraform owner.

All eight root URL/ARN outputs retain their names, for example:

```sh
terraform output -raw ecr_dev_x64_backend_url
terraform output -raw ecr_dev_x64_backend_arn
```

Repositories retain mutable tags, default encryption, no lifecycle policy, and
`force_delete = false`. CI automatically runs checks on pushes to `main`; environment
approval starts the x64 build and push to ECR in one job. This root does not build or publish images.

## Existing repositories

Check existing state ownership before creating repositories. An existing
repository in AWS needs to be imported if this state does not already own it.

For a repository not managed by another state:

```sh
terraform import -var-file=tf.vars module.ecr.aws_ecr_repository.dev_x64_backend dev/random-generator-repository/x64/backend
terraform plan -var-file=tf.vars
```

Repeat for each existing repository. Resource names are `dev_x64_backend`,
`dev_x64_frontend`, `preprod_x64_backend`, and `preprod_x64_frontend`.
The import ID is the corresponding repository name from your variables.
Do not delete repositories to resolve name conflicts.

If a different state owns these repositories, back up both states and transfer
ownership before applying the new root:

1. In the old root, replace the ECR module call with the block below and remove
   references to its outputs. If the old module address differs, use that address.
2. Plan and verify the repositories will be forgotten without destruction.
   Apply only after reviewing all other changes in that plan.
3. Import each repository into this root using the commands above.
4. Verify the new plan proposes no repository replacements or deletions and the
   old state no longer owns the repositories.

```hcl
removed {
  from = module.ecr
  lifecycle {
    destroy = false
  }
}
```

Follow [HashiCorp's remove-and-import guidance](https://developer.hashicorp.com/terraform/language/state/refactor).
Do not let two states manage the same repositories, or copy the entire application
state into this directory. State transfer is a separate explicit operation.

## State and cleanup

This root uses its own local `terraform.tfstate`. Its `tf.vars`, state, plans,
provider cache, and lockfile follow the repository's existing ignore rules.
Application infrastructure uses a separate state; destroying it leaves ECR intact.

To review and remove ECR resources intentionally:

```sh
terraform plan -destroy -var-file=tf.vars
terraform destroy -var-file=tf.vars
```

Nonempty repositories cannot be destroyed because `force_delete` remains false.
Keep state until cleanup is complete.

If repositories removed from this configuration are already managed in your
local state, the next plan will propose deleting them. Review that plan before
applying; nonempty repositories remain protected by `force_delete = false`.
Remove obsolete repository assignments from your local `tf.vars` as well.
