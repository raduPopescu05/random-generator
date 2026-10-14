# Random Generator on EKS Fargate

Configure one file, apply Terraform, then run the deployment script. Terraform
creates AWS infrastructure; the script installs the controller and application.
There is no AWS deployment hidden inside a Terraform provisioner.

## Quick start

You need Terraform >= 1.11 and < 2.0, AWS CLI v2, kubectl compatible with Kubernetes
1.35, Helm 3, and Python 3. Python needs no additional packages. Authenticate your
AWS CLI before starting.

From the repository root:

```bash
cd eks_with_terraform
cp terraform.tfvars.json.example terraform.tfvars.json
```

Edit **only `terraform.tfvars.json`**:

| Field | What to supply |
| --- | --- |
| `aws_profile` | Your configured AWS profile name, or `null` to use environment/default credentials |
| `admin_principal_arn` | IAM user or role ARN used by your AWS CLI; not an STS assumed-role session ARN |
| `public_access_cidrs` | Your public egress IP with `/32`, or a restricted VPN CIDR; replace the example address |
| `backend_image` | Complete URI of your existing linux/amd64 backend image, including tag or digest |
| `frontend_image` | Complete URI of your existing linux/amd64 frontend image, including tag or digest |
| `region`, `cluster_name`, `kubernetes_version` | Defaults are `eu-central-1`, `random-generator-eks`, and `1.35` |

The image examples use the preprod/x64 repositories targeted by the current CI
workflow. Change them if your images are elsewhere. Prefer immutable tags or
digests. The example IP and administrator ARN must be replaced.

**Step 1 — Create the infrastructure:**

```bash
terraform init
terraform apply
```

Review Terraform's plan and approve it when ready. Terraform automatically reads
`terraform.tfvars.json`; AWS credentials and database passwords are not placed
in this file. Optionally use `terraform plan -out=deployment.tfplan` followed by
`terraform apply deployment.tfplan` to review and apply a saved plan.

**Step 2 — Deploy the application:**

```bash
python3 deploy.py
```

The script automatically:

1. Reads the applied Terraform outputs, including VPC ID and controller role ARN.
2. Creates a project-local kubeconfig and checks cluster access.
3. Configures CoreDNS for Fargate and waits for readiness.
4. Renders Helm settings and installs the pinned AWS Load Balancer Controller.
5. Creates the application namespace and generates development database passwords
   directly into a Kubernetes Secret, or reuses that Secret if it already exists.
6. Renders the app manifests with your image URIs, then deploys MySQL, backend,
   frontend and Ingress in order, waiting for each deployment.
7. Waits for the controller-created ALB and checks `/health/ready` and `/history`.
8. Prints the application's HTTP URL.

No manual VPC/role copying, Helm values editing, password files, or individual
kubectl deployment commands are needed. Source manifests remain plain YAML;
rendered files and kubeconfig live in ignored `.local/`. Your global kubectl
context is not changed.

## Update or retry

Edit the same JSON configuration, then run:

```bash
terraform apply
python3 deploy.py
```

Image-only changes update Terraform's output values; they do not replace the
cluster. The script refuses to use stale applied images or settings if your
local configuration has changed without a Terraform apply.

You can rerun the script after fixing a failure. It reuses the database Secret,
reapplies resources, and refreshes the backend/frontend deployments so new image
tags and mounted Nginx configuration take effect. It does not deliberately
restart MySQL on each run. Changes to its pod specification can still replace it.

If you keep a mutable `latest` tag, pushing a new image does not update running
pods. Rerunning `python3 deploy.py` restarts the application pods and pulls it.
If the disposable MySQL pod was replaced, rerunning the script also restarts the
backend so its startup code recreates the database table.

Existing deployments using the old README can adopt this workflow: migrate
settings into `terraform.tfvars.json`, move the old `terraform.tfvars` into
`.local/` to avoid conflicting configuration, and run `terraform apply` to publish
the new outputs. An existing `app-db` Secret is retained.

## Remove the deployment

```bash
python3 deploy.py down
terraform destroy
```

`down` deletes Ingress while the controller is still running, waits for tagged
ALBs, target groups and security groups to disappear, then deletes the application
namespace and uninstalls the controller. It stops on errors or incomplete cleanup
rather than telling you to destroy the cluster prematurely. The cleanup check
requires the operator to have `tag:GetResources` permission.

Run `terraform destroy` only after application cleanup succeeds. Terraform does
not track the controller-created ALB. Destroying the cluster first can orphan AWS
resources. The script never runs Terraform apply/destroy itself, never strips
Ingress finalizers, and refuses to uninstall the controller if other ALB
Ingresses are still present. It uses the deployed Terraform outputs for cleanup,
even if you have since edited the local configuration.

## Architecture and ownership

```text
Browser --HTTP:80--> public ALB --> web/Nginx --> api:3000 --> db:3306
                                    Fargate pods in private subnets
```

| Owner | Resources |
| --- | --- |
| Terraform | VPC, two public/two private subnets, one NAT, EKS, Fargate profiles, IAM and administrator access |
| Helm | AWS Load Balancer Controller and its internal webhook certificate |
| Application YAML / deployment script | Namespace, ConfigMaps, Secret, Deployments, internal Services, Ingress |
| Load balancer controller | ALB, listeners, target groups, security-group rules and pod registration |

This folder has independent local Terraform state. Only the networking module
was copied and adapted from the EC2 example. There are no custom AMIs, EC2 worker
nodes, RDS instances, persistent volumes, cert-manager installations or custom
application Helm charts.

The application has one replica per component. MySQL uses `emptyDir`: data
survives a container restart within the same pod, but disappears on pod
replacement or namespace deletion. This is a disposable development environment.
EKS, Fargate, NAT, ALB and traffic incur AWS charges while deployed.

The public Kubernetes API is restricted to your configured CIDRs; private API
access allows Fargate pods to communicate from inside the VPC. The app's ALB is
separately public on HTTP port 80. Backend and MySQL Services stay internal.
CoreDNS is explicitly configured for Fargate with one replica for this lab.

The controller receives IAM permissions through IRSA, scoped to its service
account. Fargate's execution role handles image pulls; cross-account ECR also
requires permissions in the image owner's repository policy. MySQL is pulled
from Docker Hub through NAT.

## Versions and maintenance

- AWS provider 6.x, pinned by `.terraform.lock.hcl`.
- Controller chart **1.14.1**, image **v2.14.1**.
- MySQL **8.4**; user-selected linux/amd64 app images.

Vendored IAM policy:
https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json

Chart source: https://aws.github.io/eks-charts/aws-load-balancer-controller-1.14.1.tgz
SHA-256: `5b9f5bf3d7295d0c61eda2a7aea8c7f3369d51eca406c3dc032b84eacc3893d3`.

For a future controller upgrade, update the vendored IAM policy, image tag in
`platform/controller-values.example.yaml`, and chart version in `deploy.py`
together. Apply Terraform, explicitly update the new chart's CRDs, then rerun the
script. Helm does not upgrade existing CRDs automatically. This first version
installs/reapplies the pinned release; it is not an automatic version updater.

The EKS-created cluster security group's self-ingress permits control-plane
access to the controller's TCP 9443 webhook on Fargate. Do not remove this rule.
The chart manages that webhook certificate without requiring application HTTPS.

## Troubleshooting and manual inspection

The script uses `.local/kubeconfig`. To inspect the same cluster:

```bash
export KUBECONFIG="$PWD/.local/kubeconfig"
# Use the same AWS_PROFILE configured in terraform.tfvars.json, if applicable.
kubectl -n random-generator get pods -o wide
kubectl -n random-generator get ingress
kubectl -n random-generator logs deployment/api --tail=50
kubectl -n kube-system logs deployment/aws-load-balancer-controller --tail=50
```

- Access denied/API timeout: check the AWS profile, administrator ARN, and current
  public IP allowlist. Profile authentication must use the configured IAM user/role.
- Pending pods: inspect events, Fargate selectors, routes and execution-role permissions.
- ImagePullBackOff: check image URIs, amd64 support and ECR permissions.
- DNS failures: check CoreDNS rollout and the system Fargate profile.
- Webhook errors: inspect controller logs and control-plane access to port 9443.
- ALB 503: check application readiness and MySQL; initial registration takes time.
- Database table missing after MySQL replacement: rerun deployment to recreate the
  schema through backend startup. History is intentionally lost.
- Cleanup timeout: inspect controller logs and tagged AWS resources before retrying.
  Do not bypass finalizers or proceed with Terraform destruction.

## Validation

Local checks (no AWS deployment):

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
python3 -m unittest discover -s tests -v
```

The script's tests mock all external commands. The generated application YAML and
Helm chart can also be rendered/schema-checked locally. Live IAM permissions,
Fargate scheduling, webhook reachability and ALB connectivity require deployment;
local checks cannot establish those results.
