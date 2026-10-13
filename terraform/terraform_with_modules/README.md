# Modular Terraform example

This is a separate deployment example of the original root configuration.
It creates a public HTTPS ALB with a self-signed development certificate and a single private EC2 running Docker Compose
from your custom AMI. It has its own local state in this directory.
Applying it creates a new stack; it does not manage or migrate the original
folder's resources. Never copy state or saved plans between the two examples.

## Modules

| Module | Owns | Inputs from other modules | Outputs |
| --- | --- | --- | --- |
| network | VPC, two public subnets, private subnet, internet gateway, NAT/EIP, routes | None | VPC ID and subnet IDs |
| application | EC2, instance security group/outbound rule, IAM profile and ECR/SSM permissions, runtime cloud-init | VPC ID, private subnet ID | Instance ID and security group ID |
| load_balancer | ALB, ALB security group/public ingress, HTTP redirect, HTTPS listener, self-signed ACM certificate, target group | VPC ID, public subnet IDs | URL, public certificate PEM, target group ARN, security group ID |

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
Set-Location terraform/terraform_with_modules
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

Keep .terraform.lock.hcl under version control for reproducible AWS and TLS
provider versions. To include checksums for development and CI platforms:

```powershell
terraform providers lock -platform=darwin_arm64 -platform=windows_amd64 -platform=linux_amd64
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
terraform -chdir=terraform/terraform_with_modules from the repository root.

The app takes time to pull images and become healthy after EC2 creation. Its
endpoint uses HTTPS with a self-signed certificate. Check startup through Session Manager as described in
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

## Development HTTPS without a domain

Terraform creates the ALB first, generates an RSA-2048 self-signed certificate
with the ALB's AWS hostname in its DNS subject alternative name, imports it into
ACM in the configured region, then attaches it to the HTTPS listener. Your AWS
Terraform identity also needs ACM import, describe, tagging, and delete permissions.
No domain purchase, DNS validation, or extra input variables are required.

Port 80 redirects to HTTPS on port 443 with HTTP 301, preserving the path and
query string. TLS terminates at the ALB using a TLS 1.2/1.3 policy; traffic to
EC2 and the target health check remains HTTP on port 80. The AMI and application
code need no HTTPS configuration.

Browsers and ordinary HTTP clients do not trust this self-signed certificate by
default. A warning is expected until you explicitly trust the public certificate.
For a scoped check with curl, export the public certificate and use --cacert;
this checks both certificate trust and the ALB hostname without disabling TLS
verification. From this directory, in Bash/zsh after applying:

```bash
terraform output -raw certificate_pem > /tmp/random-generator-alb.pem
app_url="$(terraform output -raw application_url)"
curl --cacert /tmp/random-generator-alb.pem "$app_url/health/ready"
curl -I "${app_url/https:/http:}/history?limit=10"
```

The health endpoint should return HTTP 200; the HTTP request should return 301
with an HTTPS Location preserving /history?limit=10. In a browser, after explicitly
trusting the certificate, check the frontend, generation buttons, and history.
Only the public certificate is exported; never share the private key or state.
If you import the certificate into a local trust store, remove the trust entry
when the development stack is destroyed or the certificate is replaced.

The private key is stored in Terraform state. Keep state and saved plans private.
The certificate lasts 365 days; Terraform renews it on an apply during its final
30 days (or after expiration). ACM does not automatically renew imported
certificates. Reapply before expiration and export/trust the replacement public
certificate. Recreating the ALB changes its hostname and generates a matching
certificate. This configuration is intended for development.
