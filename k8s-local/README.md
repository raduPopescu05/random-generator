# Deploy ECR images to Rancher Desktop Kubernetes

**Run every repository-relative command from the repository root (`random-generator/`), not from `k8s-local/`, `docker/backend/`, or `docker/frontend/`.**

On this Mac:

```bash
cd "/Users/bigradu/Desktop/MacBook-Pro/Codex-Projects /random-generator"
```

On another machine, use its repository location:

```bash
cd /path/to/random-generator
```

The commands below use **Bash**. If your terminal uses another shell, run `bash` first, then change to the repository root. On Windows, run them in WSL Ubuntu with Rancher Desktop's WSL integration enabled.

This is a manual deployment into Rancher Desktop's built-in Kubernetes. There is no deployment script or local image build. The application Deployments use these exact ECR images:

```text
834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/arm/backend:latest
834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/arm/frontend:latest
```

Both Deployments use `imagePullPolicy: Always` and the `ecr-registry` image pull Secret. The frontend repository path is based on the supplied repository name; both originally supplied console links pointed to the backend page. Confirm that the frontend repository and its `latest` tag exist before deployment.

## 1. Create the cluster through Rancher Desktop

Open Rancher Desktop, select **dockerd (Moby)** as the container engine, enable **Kubernetes**, and wait for startup to finish. Rancher Desktop creates and manages the cluster. Approximately 4 CPUs and 6 GB of available memory is a reasonable starting allocation for this application and monitoring.

Required command-line tools: `kubectl`, AWS CLI v2, Bash, and curl. Configure your AWS CLI credentials before continuing. The AWS identity needs ECR authentication and image-pull access to the two repositories above. First startup needs internet access to download the images.

## 2. Select and inspect the cluster

Do this once before following the deployment steps: clear the previous kubeconfig override and switch back to Rancher Desktop. All subsequent commands use this selected context, so you do not need to repeat it on each command.

```bash
unset KUBECONFIG
kubectl config use-context rancher-desktop
kubectl get nodes -o wide
kubectl get nodes -L kubernetes.io/arch
kubectl get storageclass
```

Expected: the Rancher node is `Ready`, its architecture is listed, and a default StorageClass is available for MySQL. Rancher Desktop normally supplies `local-path`. This workflow uses your normal Kubernetes configuration; it does not use a kubeconfig in this repository.

## 3. Create the namespace

```bash
kubectl apply -f k8s-local/manifests/namespace.yaml
kubectl config set-context --current --namespace=random-generator
kubectl get namespaces
kubectl get pods
```

Expected: `random-generator` is Active. An empty pod list is normal at this stage. Ordinary `kubectl` commands now use Rancher Desktop and this namespace. In another terminal, select that same context and namespace before using ordinary commands.

## 4. Create the ECR image pull Secret

With your AWS CLI authenticated, run this after creating the namespace:

```bash
kubectl -n random-generator create secret docker-registry ecr-registry \
  --docker-server=834251003876.dkr.ecr.eu-central-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region eu-central-1)"
```

Expected: `secret/ecr-registry created`. Kubernetes uses this Secret to pull the private ECR images. If it already exists, use the refresh command in step 11. Tokens expire after **12 hours**.

The images must support the node architecture shown in step 2. ARM-only images will not run on a typical AMD64 Windows node without compatible images or emulation.

## 5. Apply the single application Secret

One file contains the demo credentials for the API, MySQL, and Grafana:

```bash
kubectl apply -f k8s-local/manifests/secrets.yaml
```

The Secret is named `database`. Each workload reads only the keys it needs. These are disposable local POC passwords. Grafana's login is **admin / local-grafana-password**. No password prompts or application `.env` files are needed. The ECR image-pull Secret from step 4 remains separate because it supplies registry authentication.

If MySQL already has data initialized with different passwords, set `DB_USER`, `DB_PASSWORD`, and `MYSQL_ROOT_PASSWORD` in this file to match that database before applying it. Applying a Secret does not change passwords inside an existing database.

## 6. Deploy MySQL and wait for readiness

```bash
kubectl apply -f k8s-local/manifests/configmap.yaml
kubectl apply -f k8s-local/manifests/database.yaml
kubectl -n random-generator rollout status statefulset/db --timeout=300s
kubectl get pods,pvc
```

Expected: `db-0` is `1/1 Running` and `data-db-0` is `Bound`. MySQL uses the default storage class. Stop and inspect errors if readiness fails:

```bash
kubectl describe pod db-0
kubectl logs db-0
kubectl get events --sort-by=.lastTimestamp
```

## 7. Deploy the API and frontend from ECR

```bash
kubectl apply -f k8s-local/manifests/api.yaml
kubectl apply -f k8s-local/manifests/frontend.yaml
kubectl -n random-generator rollout status deployment/api --timeout=300s
kubectl -n random-generator rollout status deployment/frontend --timeout=300s
kubectl get pods
```

Expected: API, frontend, and database pods are ready. Kubernetes pulls the images from ECR itself. No local build or image import is required. For `ImagePullBackOff`, use `kubectl describe pod <pod-name>` and check the exact repository/tag, image architecture, and the age and permissions of the ECR token.

## 8. Deploy Prometheus and Grafana

Create the ConfigMaps directly from the monitoring files:

```bash
kubectl -n random-generator create configmap prometheus-config \
  --from-file=prometheus.yml=k8s-local/monitoring/prometheus.yml --dry-run=client -o yaml |
  kubectl -n random-generator apply -f -

kubectl -n random-generator create configmap grafana-datasource \
  --from-file=datasource.yml=k8s-local/monitoring/datasource.yml --dry-run=client -o yaml |
  kubectl -n random-generator apply -f -

kubectl -n random-generator create configmap grafana-provider \
  --from-file=provider.yml=k8s-local/monitoring/provider.yml --dry-run=client -o yaml |
  kubectl -n random-generator apply -f -

kubectl -n random-generator create configmap grafana-dashboards \
  --from-file=overview.json=k8s-local/monitoring/overview.json --dry-run=client -o yaml |
  kubectl -n random-generator apply -f -

kubectl apply -f k8s-local/manifests/monitoring.yaml
kubectl -n random-generator rollout status deployment/prometheus --timeout=300s
kubectl -n random-generator rollout status deployment/grafana --timeout=300s
```

## 9. Inspect the deployment

```bash
kubectl get pods
kubectl get services
kubectl get pvc
```

Expected: five ready pods (API, frontend, MySQL, Prometheus, and Grafana) and a bound MySQL volume. In Rancher Desktop's Kubernetes resource view, select the **random-generator** namespace. These resources belong to the built-in Rancher cluster.

## 10. Open the app and Grafana

Leave this command running in one terminal:

```bash
kubectl -n random-generator port-forward --address 127.0.0.1 service/frontend 8080:80
```

Open [http://localhost:8080](http://localhost:8080).

In another terminal, run:

```bash
kubectl -n random-generator port-forward --address 127.0.0.1 service/grafana 3001:3000
```

Open [http://localhost:3001/d/local-app-overview](http://localhost:3001/d/local-app-overview). Sign in with **admin / local-grafana-password**, as defined in `k8s-local/manifests/secrets.yaml`.

**If a port is occupied by the previously running deployment**, use `8081:80` for the frontend and `3002:3000` for Grafana, then open localhost ports 8081 and 3002. Nothing in this walkthrough stops the previous deployment. A page already available on 8080 does not prove this Rancher deployment is running.

Port forwarding binds only to localhost. Press Ctrl+C to stop a forward; pods keep running. Restart the forwarding command if the selected pod is replaced.

### Check the app, persistence, and metrics

With the frontend port-forward running, use another terminal. Adjust the port if you chose 8081:

```bash
curl --fail http://localhost:8080/
curl --fail http://localhost:8080/api
curl --fail http://localhost:8080/number
curl --fail http://localhost:8080/letter
curl --fail http://localhost:8080/rock-paper-scissors
curl --fail http://localhost:8080/history
```

Note the history records. Replace the API pod, wait for recovery, and check history again:

```bash
kubectl -n random-generator delete pod -l app=api
kubectl -n random-generator rollout status deployment/api --timeout=300s
curl --fail http://localhost:8080/history
```

Then replace MySQL and verify the same records survive:

```bash
kubectl -n random-generator delete pod db-0
kubectl -n random-generator rollout status statefulset/db --timeout=300s
kubectl -n random-generator rollout status deployment/api --timeout=300s
curl --fail http://localhost:8080/history
```

Pod replacement causes a brief interruption because there is one API replica and one database replica. Allow recovery if the endpoint initially returns 503; inspect the pods if it persists. MySQL history survives pod replacement through its PVC. The previous deployment's data is not copied into this database.

Generate requests and allow at least two Prometheus scrapes for Grafana's charts. To inspect scrape health directly, run a temporary forward in another terminal:

```bash
kubectl -n random-generator port-forward --address 127.0.0.1 service/prometheus 9090:9090
```

Open `http://localhost:9090/targets`; `random-generator-api` should be UP. Check the Grafana overview for actual request/generation metrics. Prometheus and Grafana storage is temporary, so their history and manual UI changes may disappear after a restart.

## 11. Deploy a newly published latest image

If the ECR token has expired, refresh the existing Secret:

```bash
kubectl -n random-generator create secret docker-registry ecr-registry \
  --docker-server=834251003876.dkr.ecr.eu-central-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region eu-central-1)" \
  --dry-run=client -o yaml |
  kubectl -n random-generator apply -f -
```

Then restart both application Deployments:

```bash
kubectl -n random-generator rollout restart deployment/api deployment/frontend
kubectl -n random-generator rollout status deployment/api --timeout=300s
kubectl -n random-generator rollout status deployment/frontend --timeout=300s
```

`Always` makes each new pod resolve the registry's current `latest` image. Publishing a new tag value alone does not restart existing pods. Restart the frontend port-forward if it exits during this rollout.

If monitoring files change, repeat the ConfigMap commands in step 8, then restart monitoring to reload them:

```bash
kubectl -n random-generator rollout restart deployment/prometheus deployment/grafana
```

## 12. Remove the application — destructive

**Only run this when you want to delete the application and all database history in the `random-generator` namespace.** It deletes the namespace and its PVC; the normal local storage provisioner removes the associated data. Rancher Desktop's Kubernetes cluster remains running.

```bash
kubectl delete namespace random-generator --wait=true --timeout=300s
```

Stop any port-forward terminals with Ctrl+C. This cleanup does not remove the previously created separate cluster or any AWS resources.

## Validation status

This revision is **untested at runtime**. Only repository file edits were made; no commands, image inspection, deployment, or cleanup were performed on your Mac. Run the checks above yourself, including architecture compatibility and Windows/WSL behavior where applicable. Existing test results from other deployment methods do not validate this revision.
