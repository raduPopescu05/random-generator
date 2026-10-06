# Private EC2 + Docker Compose

`main.tf` creates the complete example: two public subnets, one private subnet,
an HTTP Application Load Balancer, one NAT gateway, and one private Ubuntu EC2
instance running Nginx, the Node backend, and MySQL with Docker Compose.

The instance now requires a **manually prepared custom AMI**. Terraform supplies
runtime configuration only; it does not install software or create Compose,
Nginx, scripts, or systemd units. AMI creation is a separate future step.

```text
Browser -> public ALB:80 -> private EC2:80 -> Nginx -> api:3000 -> db:3306
                               |
                               +-> NAT gateway -> registries, packages, SSM
```

Only the frontend is published on the instance. MySQL and the API are internal
to Docker. Administration uses AWS Systems Manager Session Manager; no SSH key,
inbound SSH port, or public instance IP is needed. The ALB's public DNS name is
the application address. One EC2 instance and one NAT gateway are intentional
single points of failure for this example.

## Configure locally

Install Terraform 1.11 or newer (below 2.0). AWS CLI and the Session Manager
plugin are needed on your computer if you want command-line sessions; the AWS
console also supports Session Manager.

Use the ignored `tf.vars` file created locally. In a fresh clone:

```powershell
Copy-Item tf.vars.example tf.vars
```

Fill in `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN`
when using temporary credentials. Alternatively leave these null and use your
normal AWS environment variables or profile. Do not paste keys into `main.tf`.
Terraform reads `tf.vars` only when explicitly given `-var-file="tf.vars"`.
AWS CLI commands do **not** read this file; authenticate your CLI separately.

Choose distinct database passwords of at least 16 characters. Change the example
placeholders before deployment. Runtime values are shell-quoted to preserve
dollar signs and quotes. Do not use `root` as `DB_USER`.
Use three non-overlapping subnet CIDRs contained within `VPC_CIDR`.

Instance type and root disk size are configurable. The default `t3.small` is a
starting point, not a capacity guarantee; MySQL and Node share its 2 GiB RAM.
Set `AMI_ID` to your custom AMI in `REGION`, accessible to your AWS account.
The placeholder deliberately fails input validation until replaced. There is no
automatic Ubuntu image discovery or fallback. Choose an x86-64 instance type
compatible with the AMI, and a disk at least as large as its root snapshot.
Both application images must also support linux/amd64.

ECR images must already exist in `REGION`. The default region is `eu-central-1`.
Changing region also requires changing image URIs to repositories there. The
instance role can pull only the two configured repositories; cross-account ECR
also requires a repository policy in the image-owning account. MySQL is pulled
from Docker Hub.

Your Terraform identity needs permissions to manage VPC networking, EC2, ELBv2,
IAM roles/policies/instance profiles and `iam:PassRole`, and to discover images
and availability zones. Session Manager operators separately need permission to
start sessions. No AWS resources are created by `init` or `validate`.

## Validate, plan, and deploy

Run from the repository root:

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan -var-file="tf.vars" -out="deployment.tfplan"
# Review the proposed resources and replacements before executing the saved plan.
terraform apply deployment.tfplan
terraform output -raw application_url
terraform output -raw instance_id
```

`terraform.tfstate` stays locally. Preserve it to manage and destroy this
deployment. Keep `.terraform.lock.hcl` in Git for reproducible provider selection.
`tf.vars`, state, backup state, saved plans, and `.terraform/` are ignored by Git
and excluded from Docker build contexts.

Sensitive variables hide values in normal Terraform output, but do not encrypt
local state or saved plans. Database passwords are also present in EC2 user data,
cloud-init files, and the root-readable runtime environment file. Restrict access
to those files and to EC2 user-data APIs. AWS provider keys are not embedded in
EC2 startup configuration; the server authenticates with its instance role.

ALB, NAT gateway, EC2, disk, public IPv4, and traffic incur charges. Stopping EC2
does not stop charges for the other resources. There is no HTTPS or domain setup.

## Required custom AMI contract

Prepare the image separately with Ubuntu x86-64, Docker Engine, the Compose
plugin, AWS CLI, cloud-init, and SSM agent installed. Enable Docker and SSM at
boot. Clean cloud-init's prior instance state before capturing the AMI so new
instance user data runs. Do not bake credentials, registry tokens, runtime.env,
or MySQL data into the image.

The AMI must provide these root-owned files:

| Path | Required behavior |
| --- | --- |
| `/opt/random-generator/compose.yaml` | Uses exported `BACKEND_IMAGE`, `FRONTEND_IMAGE`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, and `DB_ROOT_PASSWORD`. Runs MySQL 8.4, API and frontend with health checks, dependency ordering, restart policies, and a named database volume. Only frontend port `80:80` is published. |
| `/opt/random-generator/nginx.conf` | Mounted into frontend; proxies API routes including `/history` to `api:3000` and `/health/ready` to the backend readiness endpoint. |
| `/opt/random-generator/pull-images.sh` | Executable; loads runtime settings, derives registry hosts from image URIs, logs in using `AWS_REGION` and the EC2 role, and pulls images with bounded retries. Returns nonzero on failure. |
| `/opt/random-generator/start-app.sh` | Executable, idempotent helper invoked by cloud-init. Checks required files/settings, runs the pull helper, and enables/restarts `random-generator.service`; fails visibly if setup is incomplete. |
| `/etc/systemd/system/random-generator.service` | Starts after Docker/network availability. Sources runtime settings before Compose starts with readiness waiting; stops Compose on shutdown. Enabled by the startup helper after initial configuration. Reboots reuse downloaded images without requiring ECR access. |

Terraform writes only `/opt/random-generator/runtime.env`, owned by root with
mode `0600`. It contains Bash single-quoted assignments for `AWS_REGION`,
`BACKEND_IMAGE`, `FRONTEND_IMAGE`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, and
`DB_ROOT_PASSWORD`. Embedded single quotes are escaped for Bash. No AWS access
keys are written.

Every helper and the service's shell wrapper must load this file as follows:

```bash
set -euo pipefail
set -a
source /opt/random-generator/runtime.env
set +a
cd /opt/random-generator
# Run Docker Compose here with the exported settings.
```

This is a **Bash environment file**, not a Compose `--env-file` or systemd
`EnvironmentFile`. Those parsers have different quoting rules. The systemd unit
must invoke a Bash wrapper that sources the file. In Compose, map
`DB_PASSWORD` to both the API password and MySQL's `MYSQL_PASSWORD`, and map
`DB_ROOT_PASSWORD` to `MYSQL_ROOT_PASSWORD`. Keep `DB_HOST=db` and `DB_PORT=3306`.

The existing repository Compose file alone is not sufficient for the AMI: it has
hardcoded credentials and port 3000 published. The later manual AMI preparation
must implement this contract before the first deployment.

## Startup and access

Terraform creates the instance, but cloud-init completes asynchronously. Allow
several minutes for image downloads and service startup, followed by ALB
health checks. An initial HTTP 503 can mean startup has not completed.

Cloud-init writes runtime.env and invokes the AMI's start-app.sh helper. That
helper logs into ECR using the role, retries image pulls, and starts the service.
The service starts existing images on reboot without requiring a new registry
login. Database and API health checks control Compose startup order.

The mounted Nginx configuration proxies `/history` and the other API routes to
`api:3000`. `/health/ready` forwards to the backend's database readiness check and
is used by the ALB. This deployment does not require rebuilding the frontend
image to fix the missing history route, provided the AMI supplies the corrected
mounted configuration described above.

Connect using EC2 console -> instance -> Connect -> Session Manager, or:

```powershell
$instanceId = terraform output -raw instance_id
aws ssm start-session --region eu-central-1 --target $instanceId
```

Use your configured region. The complete command is also available through
`terraform output -raw session_manager_command`.

Inside the instance:

```bash
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
sudo systemctl status random-generator --no-pager
sudo journalctl -u random-generator -n 100 --no-pager
sudo bash -c 'set -a; source /opt/random-generator/runtime.env; set +a; cd /opt/random-generator; docker compose ps'
sudo bash -c 'set -a; source /opt/random-generator/runtime.env; set +a; cd /opt/random-generator; docker compose logs --tail=100'
curl -f http://localhost/health/ready
```

If startup failed because of a temporary download or permission issue, correct
the cause, then rerun `sudo /opt/random-generator/start-app.sh`. If SSM is
unavailable, check NAT routes, instance profile, and EC2 console system logs.
Do not print runtime.env or resolved Compose configuration into shared logs:
they contain passwords.

## Refresh images and data lifecycle

Pushing new `latest` tags does not automatically deploy them. From a session:

```bash
sudo /opt/random-generator/pull-images.sh
sudo systemctl restart random-generator.service
```

This causes downtime while the stack restarts. For reproducible releases, supply
immutable tags or digests. Changing Terraform's bootstrap inputs, including image
URIs or database passwords, replaces EC2 and **deletes its database**. Changing
`AMI_ID` also replaces EC2; always read the plan.

MySQL data lives on the EC2 root disk in Docker's `mysql-data` volume. It survives
reboots and stop/start, but does not survive termination/replacement or a Compose
`down -v`. There are no backups in this example. Changing initial MySQL passwords
on an existing data volume does not rotate the existing database users.

## Verify after deployment

1. Confirm the ALB target is healthy and the output URL loads the page.
2. Generate numbers/letters and confirm `/history?limit=10` returns them.
3. Confirm `/health/ready` returns HTTP 200 through the ALB.
4. Reboot EC2 and check service recovery and that history is retained.
5. Confirm EC2 has no public IP, only port 80 ingress from the ALB, and no host
   port bindings for 3000 or 3306.

## Tear down

```powershell
terraform plan -destroy -var-file="tf.vars"
terraform destroy -var-file="tf.vars"
```

Destroy removes the application database with EC2, the load balancer, NAT, its
Elastic IP, and the other managed resources. The existing ECR repositories are
not managed or deleted. Keep the local state until destruction finishes.

References: [Docker's Ubuntu installation instructions](https://docs.docker.com/engine/install/ubuntu/)
and [Terraform AWS instance resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance).
