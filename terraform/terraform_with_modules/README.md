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

## Configure

You need Terraform >= 1.11 and < 2.0, AWS permissions for these resources, and a
custom Ubuntu x86-64 AMI in the chosen region. It must follow the
[existing AMI contract](../Terraform-Readme.md#required-custom-ami-contract):
installed Docker/Compose, AWS CLI, cloud-init, SSM, deployment files, startup
helpers, and the systemd service. Terraform only writes a root-readable
/opt/random-generator/runtime.env and invokes /opt/random-generator/start-app.sh.
There is no fallback image or software installation.

From the repository root, in PowerShell:

```powershell
Set-Location terraform_with_modules
Copy-Item tf.vars.example tf.vars
```

Edit tf.vars locally. Set your AMI ID, passwords, image URIs, and instance size.
The example uses the x64 ECR repositories discussed for this application; replace
them if your existing linux/amd64 images use different repositories. Both images
must be in REGION and accessible to the instance role. These repositories are
not created by Terraform.

Leave AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY null to use your normal AWS
profile/environment, or set matching IAM user credentials locally. Temporary
credentials can be supplied through the standard AWS environment chain with both
provider key inputs left null. No credentials are passed into the modules.

tf.vars and local state/plans are ignored by the parent .gitignore. The entire
directory is excluded from the application's Docker build context. No local
credentials, state, or provider directory were copied from the original example.
Sensitive markings hide passwords in normal output; state/user data still contain
database passwords and must be kept private.

## Validate and optionally deploy

Run from this directory:

```powershell
terraform init
terraform fmt -check -recursive
terraform validate
```

Keep .terraform.lock.hcl under version control. The original root lock file was
absent, so this example's lock file was generated offline from the already
installed AWS provider 6.67.0. Validation passed using that local package.
The lock currently contains checksums for Windows amd64 only. Before using
Linux or CI, obtain the additional official checksums with network access:

```powershell
terraform providers lock -platform=windows_amd64 -platform=linux_amd64
```

When you choose to deploy, manually run:

```powershell
terraform plan -var-file="tf.vars" -out="deployment.tfplan"
terraform apply deployment.tfplan
terraform output -raw application_url
terraform output -raw instance_id
terraform output -raw session_manager_command
```

No AWS plan or apply was run as part of creating this example. Always run these
commands in this directory, not the repository root. Alternatively, use
terraform -chdir=terraform_with_modules from the repository root.

The app takes time to pull images and become healthy after EC2 creation. Its
endpoint is HTTP only. Check startup through Session Manager as described in
the [original deployment guide](../Terraform-Readme.md#startup-and-access).

Changes to AMI_ID or runtime user data replace EC2 and delete its MySQL data.
There is one server, one NAT gateway, no backups, and ongoing AWS charges while
the resources exist. ECR repositories and the AMI are existing external inputs.

To remove only this example's stack, run from this directory:

```powershell
terraform destroy -var-file="tf.vars"
```

Keep this directory's terraform.tfstate until destruction completes. No moved
blocks or imports are used because this example starts with independent state.
