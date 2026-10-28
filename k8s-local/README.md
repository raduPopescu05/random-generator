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

Open Rancher Desktop, select **dockerd (Moby)** as the container engine, enable **Kubernetes** and **Traefik**, and wait for startup to finish. Rancher Desktop creates and manages the cluster. Approximately 4 CPUs and 6 GB of available memory is a reasonable starting allocation for this application and monitoring.

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

Expected: `secret/ecr-registry created`. Kubernetes uses this Secret to pull the private ECR images. If it already exists, use the refresh command in step 8. Tokens expire after **12 hours**.

The images must support the node architecture shown in step 2. ARM-only images will not run on a typical AMD64 Windows node without compatible images or emulation.

## 5. Configure and deploy everything

Kustomize is built into `kubectl`; no extra installation is needed. It reads `k8s-local/kustomization.yaml`, combines the listed resources, replaces image aliases with configured repositories/tags, and creates the monitoring ConfigMaps from files.

| Setting | File |
| --- | --- |
| All six image repositories and tags | `k8s-local/kustomization.yaml`: edit `newName` and `newTag` |
| Database host, port, name | `k8s-local/manifests/configmap.yaml` |
| Application, MySQL, Grafana demo passwords | `k8s-local/manifests/secrets.yaml` |
| Monitoring configuration | `k8s-local/monitoring/` |

Kustomize prepares resources before deployment. ConfigMaps supply settings inside the cluster; Secrets supply credentials. A ConfigMap cannot set a Deployment image.

The single application Secret is named `database`. Grafana login is **admin / local-grafana-password**. If MySQL already has data, keep its existing credentials: applying a Secret does not change passwords inside the database. ECR authentication stays separate in step 4.

Deploy the namespace, MySQL with its exporter sidecar, API, frontend, Prometheus, Grafana, Ingress, application Secret, and all configuration together. Adding the sidecar replaces the existing MySQL pod once and briefly interrupts database access; its PVC and history are preserved. Record existing history before applying if you want to verify the upgrade.

Optional: render the configuration first with `kubectl kustomize k8s-local/`. Check the resolved images, two Ingress routes, five dashboard files, and Secret references. The output includes the demo application Secret.

Apply:

```bash
kubectl apply -k k8s-local/
```

Use `-k` for deployment. Workload manifests contain image aliases that Kustomize replaces; do not apply those manifests individually with `-f`. The resource name stays `api`.

Kustomize does not wait for MySQL before starting other workloads. Initial API readiness failures can occur while the database initializes. Wait for readiness:

```bash
kubectl rollout status statefulset/db --timeout=300s
kubectl rollout status deployment/api --timeout=300s
kubectl rollout status deployment/frontend --timeout=300s
kubectl rollout status deployment/prometheus --timeout=300s
kubectl rollout status deployment/grafana --timeout=300s
kubectl get pods,pvc
```

Expected: at least five ready pods, with `db-0` showing `2/2` Ready, and `data-db-0` Bound. If a wait fails, inspect the affected pod:

```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl get events --sort-by=.lastTimestamp
```

For `ImagePullBackOff`, check repository/tag, architecture, ECR permissions and token age. For a pending PVC, check the default StorageClass. Reapplying preserves the existing MySQL volume and history.

## 6. Inspect the deployment

```bash
kubectl get pods
kubectl get services
kubectl get pvc
```

Expected: at least five ready pods (API, frontend, MySQL, Prometheus, and Grafana) and a bound MySQL volume. In Rancher Desktop's Kubernetes resource view, select the **random-generator** namespace. These resources belong to the built-in Rancher cluster.

## 7. Open the app and Grafana through Ingress

**Ingress defines routing rules; Traefik receives browser traffic and forwards it to the matching Service and pods.** Rancher Desktop includes Traefik. The Ingress matches the hostname in the browser request, so both sites share HTTP port 80 while their Services remain internal. No app or Grafana terminal port-forward is needed.

```text
Browser → Traefik :80 → Ingress host rule → Service → Pod
app.localhost         → frontend:80       → frontend → api
grafana.localhost     → grafana:3000      → Grafana
```

In Rancher Desktop Kubernetes settings, enable Traefik. If Rancher requests permission to bind privileged host ports, allow it so port 80 is reachable. Check the controller and routes:

```bash
kubectl -n kube-system rollout status deployment/traefik --timeout=300s
kubectl get ingressclass traefik
kubectl -n kube-system get service traefik
kubectl get ingress random-generator
```

Open [the app](http://app.localhost) and [Grafana](http://grafana.localhost). Grafana login is **admin / local-grafana-password**. Under **Dashboards → Random Generator**, you will find:

- API Overview
- Node.js Runtime
- Generation & Database Activity
- MySQL Overview
- Local App Overview (retained)

The four added dashboards are copies from `monitoring/grafana/dashboards/`. To bring in later root dashboard changes, copy the corresponding JSON files into `k8s-local/monitoring/` and reapply Kustomize. UIDs and the Prometheus datasource identifier are preserved. The published backend image must expose the requested metrics; missing metrics require a compatible published image, not just a dashboard update.

### Hostname and port troubleshooting

On Mac, first check the HTTP route independently of hostname resolution:

```bash
curl --fail --resolve app.localhost:80:127.0.0.1 http://app.localhost/
curl --fail --resolve grafana.localhost:80:127.0.0.1 http://grafana.localhost/api/health
```

If these work but ordinary requests do not resolve, add `127.0.0.1 app.localhost grafana.localhost` to `/etc/hosts` using an administrator editor. If your Rancher networking exposes Traefik on another reachable address, use that address instead.

If port 80 is refused, check Traefik readiness and Rancher privileged-port permissions. To identify an existing Mac listener, run `lsof -nP -iTCP:80 -sTCP:LISTEN`. On Windows use `Get-NetTCPConnection -LocalPort 80 -State Listen` in PowerShell. Resolve any conflicting listener yourself; these instructions do not stop existing services. A Traefik 404 usually indicates an unmatched hostname/rule; a 503 usually indicates an unavailable backend. Inspect `kubectl describe ingress random-generator` and pod readiness.

### Windows / WSL ingress access (unverified)

Do not assume the Mac loopback address works on Windows. Find the address published by Traefik:

```bash
kubectl -n kube-system get service traefik -o jsonpath='{.status.loadBalancer.ingress[*].ip}'
```

Select the address reachable from the Windows host. In Windows PowerShell, verify `Test-NetConnection <TRAEFIK_IP> -Port 80`, then `curl.exe --resolve app.localhost:80:<TRAEFIK_IP> http://app.localhost/`. If it is unreachable, resolve Rancher/WSL networking and firewall access before changing DNS.

Using an administrator editor, add `<TRAEFIK_IP> app.localhost grafana.localhost` to `C:\Windows\System32\drivers\etc\hosts`, replacing the placeholder. Keep the same Ingress host rules and Grafana URL. WSL command-line tools may need the same mapping in their own `/etc/hosts`; Windows browsers use the Windows-side configuration. Some browsers force `.localhost` names to loopback: if the explicit-address curl check works but the browser still ignores the mapping, use `app.rancher.test` and `grafana.rancher.test` consistently in the hosts file, Ingress rules, and Grafana `GF_SERVER_ROOT_URL`, then reapply.

See [Rancher Traefik settings](https://docs.rancherdesktop.io/ui/preferences/kubernetes/) and [Rancher Windows ingress guidance](https://docs.rancherdesktop.io/1.22/tutorials/working-with-webassembly/#ingress-ip-on-windows).

### Check the app, persistence, and metrics

Use the Ingress application URL:

```bash
curl --fail http://app.localhost/
curl --fail http://app.localhost/api
curl --fail http://app.localhost/number
curl --fail http://app.localhost/letter
curl --fail http://app.localhost/rock-paper-scissors
curl --fail http://app.localhost/history
```

Note the history records. Replace the API pod, wait for recovery, and check history again:

```bash
kubectl -n random-generator delete pod -l app=api
kubectl -n random-generator rollout status deployment/api --timeout=300s
curl --fail http://app.localhost/history
```

Then replace MySQL and verify the same records survive:

```bash
kubectl -n random-generator delete pod db-0
kubectl -n random-generator rollout status statefulset/db --timeout=300s
kubectl -n random-generator rollout status deployment/api --timeout=300s
curl --fail http://app.localhost/history
```

Pod replacement causes a brief interruption because there is one database replica and the API can scale down to one replica. Allow recovery if the endpoint initially returns 503; inspect the pods if it persists. MySQL history survives pod replacement through its PVC. The previous deployment's data is not copied into this database.

Generate requests and allow at least two Prometheus scrapes for Grafana's charts. To inspect scrape health directly, run a temporary forward in another terminal:

```bash
kubectl -n random-generator port-forward --address 127.0.0.1 service/prometheus 9090:9090
```

Open `http://localhost:9090/targets`; `random-generator-api` and `mysql` should be UP. In Prometheus, query `mysql_up{job="mysql"}` and confirm it equals `1`. An UP scrape alone does not prove MySQL authentication succeeds. Check all four added dashboards after generating traffic and allowing several scrapes.

The exporter is the second container in `db-0`. It connects to `127.0.0.1:3306` as root using `MYSQL_ROOT_PASSWORD` from the existing `database` Secret. Its HTTP probes check the exporter listener, not MySQL collection. For failures, use `kubectl logs db-0 -c mysql-exporter` and `kubectl logs db-0 -c mysql`. Keep the Secret password matched to the existing database; no new user or database reset is required.

Re-run `kubectl apply -k k8s-local/` and confirm history remains. Prometheus and Grafana storage is temporary, so their history and manual UI changes may disappear after a restart.

## 8. Deploy a newly published latest image

If the ECR token has expired, refresh the existing Secret:

```bash
kubectl -n random-generator create secret docker-registry ecr-registry \
  --docker-server=834251003876.dkr.ecr.eu-central-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region eu-central-1)" \
  --dry-run=client -o yaml |
  kubectl -n random-generator apply -f -
```

To change an image repository or tag, edit `newName` or `newTag` in `k8s-local/kustomization.yaml`, then apply:

```bash
kubectl apply -k k8s-local/
```

If you published new images under the same `latest` tag, restart both application Deployments:

```bash
kubectl -n random-generator rollout restart deployment/api deployment/frontend
kubectl -n random-generator rollout status deployment/api --timeout=300s
kubectl -n random-generator rollout status deployment/frontend --timeout=300s
```

`Always` makes each new pod resolve the registry's current `latest` image. Publishing a new tag value alone does not restart existing pods. Ingress access continues to use the same hostnames after rollout.

If monitoring files change, run `kubectl apply -k k8s-local/` again. Kustomize adds content hashes to generated ConfigMap names and updates workload references, triggering monitoring rollouts automatically. Older ConfigMaps remain until namespace cleanup. Database ConfigMap and application Secret changes do not automatically restart pods consuming them through environment variables; restart affected workloads after intentional changes. Changing MySQL passwords also requires updating credentials inside the database.

## 9. Remove the application — destructive

**Only run this when you want to delete the application and all database history in the `random-generator` namespace.** It deletes the namespace and its PVC; the normal local storage provisioner removes the associated data. Rancher Desktop's Kubernetes cluster remains running.

```bash
kubectl delete namespace random-generator --wait=true --timeout=300s
```

Stop any port-forward terminals with Ctrl+C. This cleanup does not remove the previously created separate cluster or any AWS resources.

## API Horizontal Pod Autoscaler (HPA)

Kustomize now includes an `autoscaling/v2` HPA named `api`. It scales only Deployment `api`, from **1 to 5 replicas**, targeting **70% average CPU utilization**. With a 250m CPU request per API pod, that target is approximately **175m per pod**. CPU requests and limits remain unchanged. Frontend, MySQL, Prometheus, and Grafana remain fixed at one replica.

The HPA reads the Kubernetes resource metrics API (metrics-server), not Prometheus. Check prerequisites and apply from the repository root:

```bash
kubectl top pods --containers
kubectl apply -k k8s-local/
kubectl get hpa api
kubectl describe hpa api
```

An initially unknown CPU target can occur until metrics arrive. If it persists, inspect HPA conditions and metrics-server. Refresh the ECR pull Secret using step 8 if its token has expired: newly created API pods must pull the private image. Pending pods can indicate insufficient CPU/memory on the single Rancher node. Five API replicas request 1.25 CPUs and 2.5 GiB memory in total, in addition to the other workloads. HPA adds pods, not nodes or laptop resources.

Watch autoscaling in one terminal and run a five-minute load in another:

```bash
kubectl get hpa api -w
```

```bash
bash k8s-local/load-test.sh 100 300
```

Inspect pod count and CPU as needed:

```bash
kubectl get pods -l app=api
kubectl top pods --containers
kubectl describe hpa api
```

When sustained CPU is above target, expect the desired replica count to rise, up to five. Scale-up allows at most two added pods per 60 seconds. After stopping traffic, scale-down keeps a 120-second stabilization window and removes at most one pod per 60 seconds toward the minimum of one. These are policy limits, not exact timing guarantees; controller sampling and readiness also affect timing.

Verify HPA conditions show valid metrics and scaling activity, new API pods become Ready, and latency improves under the same load. After load stops, verify the count eventually returns to one and application history remains available. A low CPU target under load means HPA may correctly stay at one; inspect frontend, database, and load-generator bottlenecks rather than assuming scaling is broken.

The API manifest intentionally omits `spec.replicas` so later applies do not override HPA decisions. The first apply removing the previously managed replica field can temporarily default it to one; the HPA then controls the count. Reapply once scaling is stable and verify it does not reset replicas.

## Load test and observe API autoscaling

Run from the repository root. This script needs Bash, curl, and standard shell utilities; it does not use Kubernetes credentials or change replicas. It works with macOS Bash and WSL Bash.

Start with 50 concurrent workers for two minutes:

```bash
bash k8s-local/load-test.sh 50 120
```

Increase load if latency and CPU remain low:

```bash
bash k8s-local/load-test.sh 100 300
bash k8s-local/load-test.sh 200 300
```

Run one load test at a time. Each worker sends one request at a time with no pause. The script stops after the selected duration; Ctrl+C terminates its workers and in-flight requests. Reports every five seconds show cumulative completed requests/second, successes, HTTP errors, network/timeouts, mean latency, and maximum latency. In-flight requests cancelled by Ctrl+C are excluded. A final summary is printed and temporary result files are removed. Limits are 200 workers and 1800 seconds.

Arguments: `workers seconds mode base-url`. The default target is `http://app.localhost`.

| Mode | Requests | Purpose |
| --- | --- |
| `api` (default) | `/api` | Exercise API request handling without database writes |
| `mixed` | Generation endpoints and history | Exercise the full application; inserts history records |
| `history` | `/history?limit=100` | Read-only database load |

```bash
bash k8s-local/load-test.sh 50 120 mixed
bash k8s-local/load-test.sh 50 120 history
```

While it runs, use another terminal:

```bash
kubectl get pods -w
```

If the cluster metrics API is available, inspect container CPU:

```bash
kubectl top pods --containers
```

If `kubectl top` reports metrics unavailable, the HPA cannot calculate CPU utilization. Check `kubectl -n kube-system get deployment metrics-server` and `kubectl -n kube-system logs deployment/metrics-server`; resolve the cluster metrics API before expecting scaling. Prometheus and Grafana do not provide this HPA metric. Watch API latency, errors, request rate, and CPU. Try browsing the app while the load runs. Stop with Ctrl+C and observe recovery.

This generates real load; it does not deliberately freeze a process. Saturation is not guaranteed: the API endpoint is inexpensive, and the client, Ingress, or frontend can bottleneck before the API. These curl workers also consume resources on the same Mac as Rancher Desktop. Mixed/history modes can bottleneck on the single MySQL pod, which adding API replicas will not fix. Confirm API CPU is the bottleneck and compare identical load parameters against your previous single-pod baseline. The load script does not modify the HPA.

The script has been reviewed as a file but has not been executed or benchmarked on your Mac.

## Validation status

This revision is **untested at runtime**. Repository files were edited and Git commands were used for the requested commit; no cluster commands, load tests, image inspection, deployment, or cleanup were performed on your Mac. Run the checks above yourself, including architecture compatibility and Windows/WSL behavior where applicable. Existing test results from other deployment methods do not validate this revision.
