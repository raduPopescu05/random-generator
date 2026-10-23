# EKS POC: Fargate and RDS

This is an independent Terraform root for the random-generator application in `eu-central-1`. It creates a dedicated VPC and EKS cluster; it does not reuse or change the existing application infrastructure or ECR repositories.

```text
Internet → ALB (HTTP :80) → frontend Service → frontend pod
                                                ↓
                                          api Service :3000
                                                ↓
                                             API pod → RDS MySQL :3306
```

The frontend and API each have one Fargate pod. The frontend's existing Nginx configuration proxies the application routes to `api:3000`. RDS is private, Single-AZ MySQL 8.4.7 on `db.t4g.micro`, with 20 GiB encrypted gp3 storage. Its ARM instance architecture is independent of the x64 application images.

## Layout and defaults

- Terraform files here manage networking, EKS, RDS, and controller IAM permissions.
- `modules/network/` is adapted from `infra-example/modules/network`, leaving that example unchanged.
- `manifests/` contains plain Kubernetes YAML with image-tag and database-host placeholders.
- `iam/load-balancer-controller.json` is the [official v2.14.1 policy](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v2.14.1/docs/install/iam_policy.json).
- `local/` is ignored and holds your populated manifests. Local state, Terraform inputs, and plan files are also ignored. The provider lockfile is tracked for this root.

Networking uses `10.60.0.0/16`, two public subnets and two private subnets in two Availability Zones, and one shared NAT gateway. The ALB uses public subnets; Fargate and RDS use private subnets. The RDS security group accepts MySQL only from the EKS primary security group attached to Fargate pods. This permits system pods as well as application pods; there is no per-pod database isolation in this POC.

The EKS module is pinned to 21.26.0 and Kubernetes to 1.35. CoreDNS runs on Fargate, with installation ordered after profile creation. There are no EC2 node groups or Auto Mode. The Kubernetes API is publicly reachable from any IP, but requires IAM authentication and authorized Kubernetes access. The application itself is public and unauthenticated over HTTP.

This is disposable infrastructure: RDS backups, deletion protection, and the final snapshot are disabled. The application uses the database administrator account for simplicity. Terraform stores the database password in local state even though the input is sensitive; protect that state and never commit it.

Running costs include the EKS control plane, Fargate application **and system** pods, NAT gateway and data processing, ALB, RDS/storage, public IPv4 addresses, and control-plane logs. Fargate adds memory overhead and rounds pod sizing to supported allocations. One NAT and one application replica trade availability for POC simplicity. There is no autoscaler or additional monitoring stack.

## Prerequisites

Install Terraform >= 1.11, AWS CLI v2, kubectl compatible with Kubernetes 1.35, Helm 3, Docker with Buildx, and Python 3. Docker is used only to verify existing images, not build them. Use Bash for the commands below.

Configure an AWS CLI profile with permission to create VPC, EKS, RDS, IAM, KMS, and logging resources. Terraform uses the standard AWS credential chain; do not put access keys in Terraform inputs. Use the IAM identity named in `admin_principal_arn` when administering Kubernetes. An assumed role must be specified by its IAM role ARN, not its STS session ARN.

Publish the backend and frontend through the existing **Publish Dev** workflow first, and record its explicit build-number tag. This directory does not change CI or create repositories.

## 1. Create AWS resources locally

From the repository root:

```bash
cd eks
cp tf.vars.example tf.vars
```

Edit `tf.vars` for your administrator identity and desired names. The example uses the inspected account's `admin` IAM user. Keep the region consistent with the dev ECR images. Supply a database password of 16–41 letters, numbers, underscores or hyphens without putting it in shell history:

```bash
read -r -s -p 'Database password: ' TF_VAR_db_password
printf '\n'
export TF_VAR_db_password
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=tf.vars -out=poc.tfplan
terraform apply poc.tfplan
rm poc.tfplan
```

Keep this shell open for Secret creation. If reopening it, enter the same password again. Do not apply an old saved plan after changing inputs. The RDS instance has no retained backup when destroyed.

## 2. Configure Kubernetes and the load balancer controller

Continue from `eks/`:

```bash
export AWS_REGION="$(terraform output -raw region)"
CLUSTER_NAME="$(terraform output -raw cluster_name)"
VPC_ID="$(terraform output -raw vpc_id)"
CONTROLLER_ROLE_ARN="$(terraform output -raw controller_role_arn)"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
kubectl config current-context
kubectl rollout status deployment/coredns -n kube-system --timeout=10m

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version 1.14.0 \
  --set image.tag=v2.14.1 \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID" \
  --set replicaCount=1 \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\\.amazonaws\\.com/role-arn"="$CONTROLLER_ROLE_ARN" \
  --wait --timeout 10m
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=10m
```

Helm creates the annotated service account; Terraform supplies its IRSA role. Region and VPC are explicit because Fargate has no EC2 instance metadata service. The controller uses IP targets, as required for Fargate. See [AWS controller installation](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html).

## 3. Select and verify dev images

Use the same explicit build-number tag for both images. These commands fail if an image is missing; do not continue until both images report `linux/amd64`.

```bash
read -r -p 'Published dev build number: ' IMAGE_TAG
export IMAGE_TAG
[[ "$IMAGE_TAG" =~ ^[0-9]+$ ]] || { echo 'Use a numeric build tag'; exit 1; }
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "$REGISTRY"

for component in backend frontend; do
  repository="dev/random-generator-repository/x64/$component"
  aws ecr describe-images --region "$AWS_REGION" \
    --repository-name "$repository" --image-ids imageTag="$IMAGE_TAG" \
    --query 'imageDetails[0].{Digest:imageDigest,Tags:imageTags}' || exit 1
  image="$REGISTRY/$repository:$IMAGE_TAG"
  docker pull --platform linux/amd64 "$image" || exit 1
  [[ "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")" == linux/amd64 ]] || exit 1
done
```

This checks the same account and region as the deployment. ECR access for running pods comes from the Fargate execution role; no Docker registry Secret is needed.

## 4. Populate and apply the manifests

Keep the committed examples unchanged. Populate an ignored copy using Terraform outputs and the selected image tag:

```bash
mkdir -p local/manifests
export DB_HOST="$(terraform output -raw db_host)"
export DB_USER="$(terraform output -raw db_username)"
python3 - <<'PY'
import os
from pathlib import Path
for source in Path('manifests').glob('*.yaml'):
    content = source.read_text()
    content = content.replace('REPLACE_WITH_RDS_HOST', os.environ['DB_HOST'])
    content = content.replace('REPLACE_WITH_BUILD_NUMBER', os.environ['IMAGE_TAG'])
    content = content.replace('834251003876.dkr.ecr.eu-central-1.amazonaws.com', os.environ['REGISTRY'])
    Path('local/manifests', source.name).write_text(content)
PY
kubectl apply -f local/manifests/namespace.yaml
```

Create the database Secret through stdin, without putting the password in a command argument or file. Do not enable shell tracing or print the Secret:

```bash
set -o pipefail
python3 - <<'PY' | kubectl apply -f -
import json, os
password = os.environ['TF_VAR_db_password']
assert password, 'Database password must be set'
print(json.dumps({
    'apiVersion': 'v1', 'kind': 'Secret',
    'metadata': {'name': 'database', 'namespace': 'random-generator'},
    'type': 'Opaque',
    'stringData': {'DB_USER': os.environ['DB_USER'], 'DB_PASSWORD': password}
}))
PY
unset TF_VAR_db_password
kubectl apply --dry-run=server -f local/manifests/
kubectl apply -f local/manifests/
kubectl rollout status deployment/api -n random-generator --timeout=10m
kubectl rollout status deployment/frontend -n random-generator --timeout=10m
kubectl get pods,services,ingress -n random-generator
```

The API creates its history table automatically. Its readiness probe checks MySQL; its liveness probe does not depend on MySQL. The frontend Service stays private behind the ALB. The API Service is also private. `/health/live`, `/health/ready`, and `/metrics` remain backend-only because the existing Nginx config does not proxy them.

Wait until the Ingress has a hostname and the ALB targets are healthy before testing. For later image updates, repeat image verification and manifest population with the new build tag, then apply. Changing only the Secret or ConfigMap requires restarting the API deployment to reload environment variables.

## 5. Verify the deployed application

These are runtime checks for your deployment; local configuration validation does not establish that AWS resources or the app are running.

```bash
ALB_DNS="$(kubectl get ingress random-generator -n random-generator -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
[[ -n "$ALB_DNS" ]] || { echo 'Wait for the Ingress hostname'; exit 1; }
curl --fail "http://$ALB_DNS/"
curl --fail "http://$ALB_DNS/api"
curl --fail "http://$ALB_DNS/number"
curl --fail "http://$ALB_DNS/letter"
curl --fail "http://$ALB_DNS/rock-paper-scissors"
curl --fail "http://$ALB_DNS/history"
kubectl rollout restart deployment/api -n random-generator
kubectl rollout status deployment/api -n random-generator --timeout=10m
curl --fail "http://$ALB_DNS/history"
```

Open `http://<ALB_DNS>` in a browser and exercise all generators. Confirm the same history records remain after the API pod is replaced. For direct backend health/metrics checks, use `kubectl port-forward -n random-generator service/api 3000:3000` and access those endpoints on localhost.

For failures, inspect `kubectl describe pod`, `kubectl logs deployment/api`, and controller logs in `kube-system`. Fargate provisioning can take several minutes. No AWS resources are created by merely checking these files into Git.

## Cleanup

Run from `eks/` against this cluster's kubeconfig. Remove the Ingress **while the controller is still running** so it can delete the ALB, target group, and associated security group. Record the ALB ARN before removal:

```bash
ALB_DNS="$(kubectl get ingress random-generator -n random-generator -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
ALB_ARN="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --query "LoadBalancers[?DNSName=='$ALB_DNS'].LoadBalancerArn | [0]" --output text)"
[[ -n "$ALB_ARN" && "$ALB_ARN" != None ]] || { echo 'Resolve the ALB before cleanup'; exit 1; }
kubectl delete -f local/manifests/ingress.yaml --wait=true --timeout=10m
aws elbv2 wait load-balancers-deleted --region "$AWS_REGION" --load-balancer-arns "$ALB_ARN"
```

Stop and investigate if deletion or the waiter fails. If deployment never reached Ingress creation, inspect controller-owned resources before proceeding; do not remove finalizers to bypass cleanup.

Once the ALB is gone:

```bash
kubectl delete namespace random-generator --wait=true --timeout=10m
helm uninstall aws-load-balancer-controller -n kube-system --wait --timeout 10m
read -r -s -p 'Database password: ' TF_VAR_db_password
printf '\n'
export TF_VAR_db_password
terraform plan -destroy -var-file=tf.vars -out=destroy.tfplan
terraform apply destroy.tfplan
rm destroy.tfplan
unset TF_VAR_db_password
terraform state list
```

All resources in this root should be removed. RDS history is permanently discarded without a final snapshot. Existing ECR repositories and published images remain. Keep the local state until cleanup succeeds; if ENIs are still detaching, allow AWS time to finish and retry Terraform cleanup.
