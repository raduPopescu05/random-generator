# Modular Terraform example

This is a separate deployment example of the original root configuration.
It creates a public HTTP ALB and a single private EC2 running Docker Compose
from your custom AMI. It has its own local state in this directory.
Applying it creates a new stack; it does not manage or migrate the original
folder's resources. Never copy state or saved plans between the two examples.

## Modules

| Module | Owns | Inputs from other modules | Outputs |
| --- | --- | --- | --- |
| network | VPC, two public subnets, private subnet, internet gateway, NAT/EIP, routes | None | VPC ID and subnet IDs |
| application | EC2, instance security group/outbound rule, IAM profile and ECR/SSM permissions, runtime cloud-init | VPC ID, private subnet ID | Instance ID and security group ID |
| load_balancer | ALB, ALB security group/public ingress, HTTP listener, target group | VPC ID, public subnet IDs | URL, target group ARN, security group ID |

Root main.tf connects the modules. It owns the ALB-to-instance security-group
rules and target attachment so neither application nor load_balancer needs the
other module as an input. The network subnet outputs explicitly depend on route
associations: EC2 waits for NAT routing and the ALB waits for public routing.
The application also waits for its IAM policies and outbound rule before booting.

Only the root providers.tf configures AWS credentials, region, and default tags.
Child modules declare the AWS provider requirement and inherit that configuration.
Variable names/defaults and resource settings are preserved from the original.
Both database password inputs remain sensitive through the module boundary.

## Deployment order

First create ECR repositories, then publish x64 images with CI, then apply this
root. Follow the [three-step guide](../README.md). Set `BACKEND_IMAGE` and
`FRONTEND_IMAGE` to the full build-number-tagged URIs reported by CI.
This root has no ECR repository inputs or remote-state dependency. If an existing
local `tf.vars` contains `ECR_*` assignments, move those assignments to the ECR
root's `tf.vars` and remove them here. Do not copy application state.

## Configure

You need Terraform >= 1.11 and < 2.0, AWS permissions for these resources, and a
custom Ubuntu x86-64 AMI in the chosen region. It must follow the
[existing AMI contract](../../../docs/terraform.md#required-custom-ami-contract):
installed Docker/Compose, AWS CLI, cloud-init, SSM, deployment files, startup
helpers, and the systemd service. Terraform only writes a root-readable
/opt/random-generator/runtime.env and invokes /opt/random-generator/start-app.sh.
There is no fallback image or software installation.

From the repository root, in PowerShell:

```powershell
Set-Location infrastructure/terraform_wth_modules/app
Copy-Item tf.vars.example tf.vars
```

Edit tf.vars locally. Set your AMI ID, passwords, image URIs, and instance size.
The example uses the x64 ECR repositories discussed for this application; replace
them if your existing linux/amd64 images use different repositories. Both images
must be in REGION and accessible to the instance role. Repositories are created separately by the [ECR root](../ecr/README.md).
Images must be published separately before the application can pull them.

Leave AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY null to use your normal AWS
profile/environment, or set matching IAM user credentials locally. Temporary
credentials can be supplied through the standard AWS environment chain with both
provider key inputs left null. No credentials are passed into the modules.

tf.vars and local state/plans are ignored by the parent .gitignore. The entire
directory is excluded from the application's Docker build context. Sensitive markings hide passwords in normal output; state/user data still contain
database passwords and must be kept private.

## Validate and optionally deploy

Run from this directory:

```powershell
terraform init
terraform fmt -check -recursive
terraform validate
```

The repository currently ignores `.terraform.lock.hcl`, local state, variable
files, saved plans, and provider caches. Preserve your local state.

When you choose to deploy, manually run:

```powershell
terraform plan -var-file="tf.vars" -out="deployment.tfplan"
terraform apply deployment.tfplan
terraform output -raw application_url
terraform output -raw instance_id
terraform output -raw session_manager_command
```

Run these commands from the `app/` directory.

The app takes time to pull images and become healthy after EC2 creation. Its
endpoint is HTTP only. Check startup through Session Manager as described in
the [original deployment guide](../../../docs/terraform.md#startup-and-access).

Changes to AMI_ID or runtime user data replace EC2 and delete its MySQL data.
There is one server, one NAT gateway, no backups, and ongoing AWS charges while
the resources exist. The AMI remains an external input. ECR repositories are managed by the separate ECR state and survive application teardown.

To remove only this example's stack, run from this directory:

```powershell
terraform destroy -var-file="tf.vars"
```

Keep this directory's terraform.tfstate until destruction completes. Follow the [ordered deployment guide](../README.md) before applying.

