# Random Generator on EKS Fargate

An independent, disposable development stack. Run all commands below from this
folder unless noted. Nothing here reuses the existing EC2/application/ALB modules
or their state. Only `modules/network` was copied and adapted from
`terraform/terraform_with_modules/modules/network`.

```text
Browser --HTTP:80--> public ALB --> web/Nginx pod --> api:3000 --> db:3306
                                     EKS Fargate, private subnets
```

| Owner | Resources |
| --- | --- |
| Terraform | VPC, two public/two private subnets, one NAT, EKS, Fargate profiles, IAM and administrator access |
| Helm | AWS Load Balancer Controller and its webhook certificate |
| kubectl / application YAML | Namespace, ConfigMaps, Secret, Deployments, internal Services, Ingress |
| Load balancer controller | ALB, listeners, target groups, security-group rules and pod registration |

There are no EC2 worker nodes, custom AMIs, RDS instances, persistent volumes,
cert-manager installations, or custom application Helm charts. Fargate supplies
the pod runtime and networking. The app's Docker Compose helpers are not used.
EKS, Fargate, NAT, ALB and network traffic incur AWS charges while deployed.

## Versions and prerequisites

- Terraform >= 1.11 and < 2.0; AWS provider 6.x, pinned by `.terraform.lock.hcl`.
- AWS CLI v2 authenticated using your normal profile/environment; no keys in tfvars.
- kubectl compatible with Kubernetes 1.35 and Helm 3. Python 3 for the example
  local password-generation command.
- EKS Kubernetes 1.35 in `eu-central-1` by default.
- AWS Load Balancer Controller **v2.14.1**, official Helm chart **1.14.1**.
- MySQL **8.4**; existing **linux/amd64** frontend/backend ECR images.

The Terraform operator needs VPC/EKS/IAM management and PassRole permissions,
including access-entry and OIDC-provider management. The configured administrator
must be the IAM user/role used by kubectl's AWS CLI authentication, not an STS
session ARN. The controller's role uses IRSA with trust scoped to
`system:serviceaccount:kube-system:aws-load-balancer-controller`.

The vendored controller policy is unmodified from:
https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json

Chart source: https://aws.github.io/eks-charts/aws-load-balancer-controller-1.14.1.tgz
SHA-256: `5b9f5bf3d7295d0c61eda2a7aea8c7f3369d51eca406c3dc032b84eacc3893d3`.
Update the chart, controller image and IAM policy together. No unversioned remote
manifests are applied in this workflow.

## 1. Create infrastructure

From the repository root:

```bash
cd eks_with_terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

- Set `admin_principal_arn` to your IAM user/role ARN. For an assumed-role session,
  get the corresponding IAM role ARN; `aws sts get-caller-identity` reports a
  session ARN, which cannot be used directly as an EKS access entry.
- Replace `public_access_cidrs` with your public egress IP `/32` or restricted VPN
  CIDR. The example address is documentation-only. Update it if your IP changes.
- Optionally change cluster name, region, or CIDRs. Subnets must be distinct,
  non-overlapping ranges inside the VPC. The default `10.43.0.0/16` differs from
  the EC2 example's VPC.

```bash
aws sts get-caller-identity
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=deployment.tfplan
terraform apply deployment.tfplan
terraform output
```

`terraform.tfvars` loads automatically. State remains local to this folder;
protect it and retain it until destruction finishes. The public Kubernetes API
is restricted to your CIDRs; private API access lets Fargate pods reach it from
inside the VPC. The browser-facing ALB is separately public on HTTP port 80.

The Fargate execution role can pull private ECR images in this account. If your
images belong to another account, that account must also allow the execution role
in its ECR repository policy. MySQL comes from Docker Hub via NAT.

## 2. Configure kubectl and CoreDNS

Run the command printed by `terraform output -raw kubeconfig_command` using the
AWS profile corresponding to `admin_principal_arn`. For the defaults:

```bash
aws eks update-kubeconfig --region eu-central-1 --name random-generator-eks
kubectl config current-context
kubectl auth can-i create deployments --namespace random-generator
kubectl -n kube-system patch deployment coredns --type=strategic \
  --patch-file=platform/coredns-patch.yaml
kubectl -n kube-system rollout restart deployment/coredns
kubectl -n kube-system rollout status deployment/coredns --timeout=10m
kubectl get nodes -L eks.amazonaws.com/compute-type
```

The patch explicitly schedules CoreDNS on Fargate and uses one replica for this
lab. Terraform deliberately leaves Kubernetes changes to kubectl. Reapply the
patch following any CoreDNS replacement or upgrade. EKS's default EC2-oriented
DaemonSets have no EC2 nodes to run on; Fargate manages its own pod networking.

## 3. Install the load balancer controller

```bash
cp platform/controller-values.example.yaml platform/controller-values.yaml
terraform output -raw cluster_name
terraform output -raw region
terraform output -raw vpc_id
terraform output -raw controller_role_arn
```

Put these values into the corresponding fields of `controller-values.yaml`.
This local file is ignored by Git. Region and VPC ID must be explicit because the
controller on Fargate cannot discover them using EC2 instance metadata.

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 1.14.1 --namespace kube-system \
  --values platform/controller-values.yaml --wait --timeout 10m
kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=10m
kubectl -n kube-system get endpoints aws-load-balancer-webhook-service
kubectl -n kube-system logs deployment/aws-load-balancer-controller --tail=50
```

The chart creates the annotated service account and webhook certificate. It does
not create the application ALB until an Ingress is applied. No cert-manager or
application HTTPS is involved. The EKS-created cluster security group's default
self-ingress allows the control plane to reach the controller's TCP 9443 webhook
on Fargate; do not remove that rule. ALB-to-pod rules are managed by the controller.

For later controller upgrades, first review the release notes and update the
vendored IAM policy plus its Terraform deployment. Download/apply the new chart's
CRDs explicitly (Helm upgrades do not update existing CRDs), then upgrade the
pinned chart and matching image tag:

```bash
mkdir -p .local
# Use the intended new chart version in both commands when upgrading.
helm show crds eks/aws-load-balancer-controller --version 1.14.1 > .local/controller-crds.yaml
kubectl apply --server-side -f .local/controller-crds.yaml
```

## 4. Deploy the application

Edit the `image` fields in `kubernetes/20-backend.yaml` and
`kubernetes/30-frontend.yaml` to select your existing images. The defaults show the
original dev/x64 repositories; the current CI workflow pushes to preprod/x64,
so select the repositories/tags that actually contain your build. Prefer immutable
tags or digests. With `latest`, a new push requires a rollout restart; running pods
are not automatically updated. Images must support linux/amd64 and contain the
backend's `/health/live` and `/health/ready` endpoints.

Create development passwords locally. Running this generation command again
changes credentials: reuse the file for an existing MySQL pod, or reset the DB
and restart the backend deliberately. Changing a Secret alone does not update
running container environment variables or existing MySQL accounts.

```bash
mkdir -p .local
python3 - <<'PY'
import os, secrets
# Exclusive creation prevents accidentally rotating an existing deployment.
fd = os.open('.local/db.env', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as f:
    f.write('DB_PASSWORD=' + secrets.token_urlsafe(24) + '\n')
    f.write('DB_ROOT_PASSWORD=' + secrets.token_urlsafe(24) + '\n')
PY
kubectl apply -f kubernetes/00-namespace.yaml
kubectl -n random-generator create secret generic app-db \
  --from-env-file=.local/db.env --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f kubernetes/01-config.yaml -f kubernetes/02-nginx.yaml
kubectl apply -f kubernetes/10-mysql.yaml
kubectl -n random-generator rollout status deployment/db --timeout=15m
kubectl apply -f kubernetes/20-backend.yaml
kubectl -n random-generator rollout status deployment/api --timeout=10m
kubectl apply -f kubernetes/30-frontend.yaml
kubectl -n random-generator rollout status deployment/web --timeout=10m
kubectl apply -f kubernetes/40-ingress.yaml
kubectl -n random-generator get ingress random-generator --watch
```

Wait for the ADDRESS field, then stop the watch with Ctrl-C. ALB health checks
may take additional time after the hostname appears. The backend creates its
schema during startup. The frontend mounts Nginx configuration that includes
`/history` and `/health/ready`; no image rebuild is needed for these routes.
After editing the mounted ConfigMap, restart the frontend because subPath mounts
do not update automatically.

## 5. Verify the deployment

```bash
kubectl -n random-generator get pods -o wide
kubectl get nodes -L eks.amazonaws.com/compute-type
alb_host=$(kubectl -n random-generator get ingress random-generator \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -f "http://$alb_host/health/ready"
curl -f "http://$alb_host/number"
curl -f "http://$alb_host/history?limit=10"
```

Open `http://<ALB hostname>` in your browser and exercise all generation buttons
and history. Verify the ALB target group becomes healthy in AWS. The ALB targets
frontend pod IPs; the controller updates registrations as pods are replaced.
Backend and MySQL Services remain internal.

Backend liveness checks process health, while readiness checks MySQL. Database
outages remove the backend/frontend from service without liveness restart loops.
The backend's startup retry window is finite; if initial DB connectivity fails,
Kubernetes retries the container. Inspect pod logs for connection errors.

**Disposable data recovery test:**

```bash
kubectl -n random-generator delete pod -l app=db
kubectl -n random-generator rollout status deployment/db --timeout=15m
kubectl -n random-generator rollout restart deployment/api
kubectl -n random-generator rollout status deployment/api --timeout=10m
curl -f "http://$alb_host/history?limit=10"
```

History should be empty after recovery. `emptyDir` survives a container restart
within the same pod, but not pod replacement. The backend initializes its table
only at startup, so **restart the backend after replacing the MySQL pod**;
otherwise a ready database can still lack the `generations` table. There is no
automated database recovery or persistent storage in this version.

Troubleshooting:

- Pending pods: inspect events and Fargate selectors, private subnet routes and
  execution-role permissions; confirm images support amd64.
- ImagePullBackOff: check the selected repository/tag and ECR account permissions.
- DNS failures: check the CoreDNS patch, rollout, and system Fargate profile.
- Ingress/webhook errors: inspect controller logs, IRSA annotation, explicit region/
  VPC settings, and cluster security-group access on 9443.
- ALB 503: check frontend/backend readiness and MySQL availability; initial target
  registration is asynchronous.
- kubectl timeout/access denied: check your public IP allowlist, AWS profile,
  administrator access entry, and selected kubectl context.

## 6. Clean up in order

Do this while the controller, its IAM role and the cluster are still available.
Capture the ALB ARN before deleting Ingress:

```bash
region=$(terraform output -raw region)
alb_host=$(kubectl -n random-generator get ingress random-generator \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
alb_arn=$(aws elbv2 describe-load-balancers --region "$region" \
  --query "LoadBalancers[?DNSName=='$alb_host'].LoadBalancerArn | [0]" --output text)
kubectl -n random-generator delete ingress random-generator --wait=true --timeout=10m
# Run the waiter only if alb_arn contains an ARN (not None/empty).
aws elbv2 wait load-balancers-deleted --region "$region" --load-balancer-arns "$alb_arn"
kubectl delete namespace random-generator --wait=true --timeout=10m
helm uninstall aws-load-balancer-controller --namespace kube-system --wait --timeout 10m
terraform plan -destroy
terraform destroy
```

Before uninstalling the controller, confirm its target groups and ALB security
group have also been removed. If deletion is stuck, inspect controller events/logs
and fix IAM/network errors; do not force-remove Ingress finalizers. Destroying the
cluster first can leave controller-created AWS resources orphaned because they
are not tracked in Terraform state. Existing ECR images remain untouched.

## Local validation (no AWS deployment)

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
mkdir -p .local
helm template aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 1.14.1 --namespace kube-system --kube-version 1.35.0 \
  --values platform/controller-values.example.yaml --include-crds > .local/controller-rendered.yaml
```

The example values contain placeholders and are suitable only for local rendering.
Use Kubernetes schema validation for the application YAML. Live validation of
IAM, scheduling, webhook reachability and ALB traffic requires an AWS deployment;
local validation alone does not establish those results.
