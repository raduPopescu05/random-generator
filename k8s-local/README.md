# Deploy ECR images to local Kubernetes

**Run repository-relative commands from the repository root (`random-generator/`).** Windows commands use **PowerShell** (Windows PowerShell 5.1 or PowerShell 7). macOS-specific commands use **Bash**. Shared single-line `kubectl` commands work in both shells; on macOS replace `curl.exe` with `curl`. The optional existing load-test script is Bash-only and is documented separately.

On this Mac:

```bash
cd "/Users/bigradu/Desktop/MacBook-Pro/Codex-Projects /random-generator"
```

On this Windows machine, in PowerShell:

```powershell
Set-Location "F:\Programare-2025\CodexStuff\random-generator"
```

This is a manual deployment using published ECR images, with no local image build. The current `kustomization.yaml` selects:

```text
834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/x64/backend:latest
834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/x64/frontend:latest
```

Both Deployments use `imagePullPolicy: Always` and the `ecr-registry` pull Secret. Confirm both repositories and tags exist. For an ARM64 Mac node, change **both** application `newName` values in `k8s-local/kustomization.yaml` from `/x64/` to `/arm/` and verify those tags support ARM64. Repository names alone do not prove image architecture. Do not rely on emulation in Kubernetes.

## 1. Choose the platform setup

### macOS: Rancher Desktop

Select **dockerd (Moby)**, enable **Kubernetes** and bundled **Traefik**, and wait for startup. Allow privileged-port access if prompted. Use the bundled controller in `kube-system`; do not install the Docker Desktop Helm release on Rancher.

Required tools: kubectl, AWS CLI v2, Bash, and curl. Start with approximately 4 CPUs and 6 GB available memory for the application and monitoring; HPA load may need more.

### Windows 11: Docker Desktop + PowerShell

1. Use Linux containers and Docker Desktop's WSL 2 engine, following [Docker's backend setup](https://docs.docker.com/desktop/features/wsl/). WSL 2 is the container backend; run all deployment commands in Windows PowerShell. A WSL terminal, Linux CLI installation, and distribution integration are not required for these commands. Avoid running Rancher Desktop concurrently against the same host ports.
2. Reuse the existing cluster in Docker Desktop's Kubernetes view. **Do not reset it or switch its provisioner.** For a fresh installation, create a single-node kubeadm cluster. Existing Docker Desktop kind clusters are also supported by this workflow. See [Docker's Kubernetes setup](https://docs.docker.com/desktop/use-desktop/kubernetes/).
3. Install Windows versions of kubectl (included with Docker Desktop), Helm, AWS CLI v2, and curl, and make them available on PATH. Open a new PowerShell terminal after installation. Keep kubectl within one minor version of the server. Use `curl.exe` explicitly to avoid Windows PowerShell's `curl` alias for `Invoke-WebRequest`.

   Install Helm using [Chocolatey](https://docs.chocolatey.org/en-us/choco/setup/). If Chocolatey is not installed, follow its setup instructions first. Open **PowerShell as Administrator** and run the [Helm Chocolatey installation command](https://docs.helm.sh/):

   ```powershell
   choco --version
   choco install kubernetes-helm -y
   ```

   Close the administrator terminal and open a new regular PowerShell terminal so PATH changes are loaded. Verify Helm before continuing:

   ```powershell
   helm version --shortex
   ```

   The Chocolatey package installs the Helm CLI; the `--version 42.3.0` used later pins the Traefik chart, not the Helm CLI.

4. Configure AWS credentials in Windows and check `aws sts get-caller-identity`. The identity needs ECR authentication and pull access. Internet access is needed for charts and images.
5. Check the Windows tools and cluster connectivity:

```powershell
Get-Command docker, kubectl, helm, aws, curl.exe
kubectl --request-timeout=10s get nodes
```

If the API is unreachable, verify Docker Desktop's Kubernetes startup and resolution of the configured API hostname. Resolve connectivity before proceeding; do not disable TLS verification or substitute a container IP blindly.

## 2. Inspect the cluster and prepare ingress

Run this in PowerShell on Windows, or Bash on macOS:

```powershell
kubectl get nodes -o wide
kubectl get nodes -L kubernetes.io/arch
kubectl get storageclass
```

Require Ready nodes, matching image architecture, and a **default** StorageClass for MySQL. Rancher normally supplies `local-path`; Docker Desktop's provisioner/name can vary. The PVC intentionally does not specify a class. A `WaitForFirstConsumer` volume may remain Pending until its pod is scheduled. If no default exists, resolve cluster storage provisioning before deploying; do not hard-code a Rancher class into the application.

### Rancher: verify the bundled controller

```bash
kubectl -n kube-system rollout status deployment/traefik --timeout=300s
kubectl get ingressclass traefik
kubectl -n kube-system get service traefik
```

### Docker Desktop: install Traefik with Helm

The [official Traefik chart](https://github.com/traefik/traefik-helm-chart/tree/v42.3.0/traefik) is pinned to **42.3.0** (Traefik **v3.7.17**, Kubernetes **1.30+**). Check `kubectl version` first. An older cluster needs a compatible chart version evaluated separately; do not reset the cluster to follow this guide.

`traefik-values.yaml` installs one replica, the Kubernetes Ingress provider and explicit `traefik` IngressClass. Its LoadBalancer Service publishes only HTTP port 8080; the dashboard is disabled and no HTTPS redirect is configured. Controller installation is separate from application Kustomize.

Before installation, check `kubectl get ingressclass` and `helm list -A`. If another release owns `traefik`, reconcile that existing installation rather than attempting a second controller.

```powershell
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik
helm template traefik traefik/traefik --version 42.3.0 --namespace traefik --kube-version 1.36.1 -f k8s-local/traefik-values.yaml
helm upgrade --install traefik traefik/traefik --version 42.3.0 --namespace traefik --create-namespace -f k8s-local/traefik-values.yaml --wait --timeout 300s
kubectl -n traefik rollout status deployment/traefik --timeout=300s
kubectl get ingressclass traefik
kubectl -n traefik get service traefik
```

For rendering, replace `1.36.1` with your server version if different. Repeating `helm upgrade --install` updates the same release. Expect a LoadBalancer Service with port 8080 and a host-reachable endpoint (normally localhost); verify actual Windows reachability in step 7. A healthy controller alone does not prove host forwarding works. No MetalLB or separate kind cluster is needed.

Continue with the shared steps below for your installed desktop platform. Application commands specify the `random-generator` namespace explicitly.

## 3. Create the namespace

```powershell
kubectl apply -f k8s-local/manifests/namespace.yaml
kubectl get namespaces
kubectl -n random-generator get pods
```

Expected: `random-generator` is Active. An empty pod list in that namespace is normal at this stage.

## 4. Create the ECR image pull Secret

On either platform, configure AWS CLI credentials in the same terminal environment and verify `aws sts get-caller-identity`. The identity needs ECR authentication and pull access. Run this after creating the namespace:

**Windows PowerShell:**

```powershell
$ecrPassword = aws ecr get-login-password --region eu-central-1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ecrPassword)) { throw "ECR authentication failed" }
kubectl -n random-generator create secret docker-registry ecr-registry --docker-server=834251003876.dkr.ecr.eu-central-1.amazonaws.com --docker-username=AWS --docker-password="$ecrPassword"
Remove-Variable ecrPassword -ErrorAction SilentlyContinue
```

**macOS Bash:**

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

The single application Secret is named `database`. Grafana login is **admin / admin**. If MySQL already has data, keep its existing credentials: applying a Secret does not change passwords inside the database. ECR authentication stays separate in step 4.

Deploy the namespace, MySQL with its exporter sidecar, API, frontend, Prometheus, Grafana, Ingress, application Secret, and all configuration together. Adding the sidecar replaces the existing MySQL pod once and briefly interrupts database access; its PVC and history are preserved. Record existing history before applying if you want to verify the upgrade.

Optional: render the configuration first with `kubectl kustomize k8s-local/`. Check the resolved images, two Ingress routes, five dashboard files, and Secret references. The output includes the demo application Secret.

Apply:

```powershell
kubectl apply -k k8s-local/
```

Use `-k` for deployment. Workload manifests contain image aliases that Kustomize replaces; do not apply those manifests individually with `-f`. The resource name stays `api`.

Kustomize does not wait for MySQL before starting other workloads. Initial API readiness failures can occur while the database initializes. Wait for readiness:

```powershell
kubectl -n random-generator rollout status statefulset/db --timeout=300s
kubectl -n random-generator rollout status deployment/api --timeout=300s
kubectl -n random-generator rollout status deployment/frontend --timeout=300s
kubectl -n random-generator rollout status deployment/prometheus --timeout=300s
kubectl -n random-generator rollout status deployment/grafana --timeout=300s
kubectl -n random-generator get "pods,pvc"
```

Expected: at least five ready pods, with `db-0` showing `2/2` Ready, and `data-db-0` Bound. If a wait fails, inspect the affected pod:

```powershell
kubectl -n random-generator describe pod "REPLACE_WITH_POD_NAME"
kubectl -n random-generator logs "REPLACE_WITH_POD_NAME"
kubectl -n random-generator get events --sort-by=.lastTimestamp
```

For `ImagePullBackOff`, check repository/tag, architecture, ECR permissions and token age. For a pending PVC, check the default StorageClass. Reapplying preserves the existing MySQL volume and history.

## 6. Inspect the deployment

```powershell
kubectl -n random-generator get pods
kubectl -n random-generator get services
kubectl -n random-generator get pvc
```

Expected: at least five ready pods (API, frontend, MySQL, Prometheus, and Grafana) and a bound MySQL volume. In your desktop application's Kubernetes resource view, select the **random-generator** namespace.

## 7. Open the app and Grafana through Ingress

**Ingress defines routing rules; Traefik receives browser traffic and forwards it to the matching Service and pods.** Rancher supplies Traefik; Docker Desktop uses the Helm release installed in step 2. The Ingress matches the hostname in the browser request, so both sites share HTTP port 8080 on Docker Desktop (port 80 on Rancher) while their Services remain internal. No app or Grafana terminal port-forward is needed.

```text
Browser → Traefik :8080 (Docker Desktop) / :80 (Rancher) → Ingress host rule → Service → Pod
app.localhost         → frontend:80       → frontend → api
grafana.localhost     → grafana:3000      → Grafana
```

Check the routes (controller readiness was checked in step 2):

```powershell
kubectl get ingressclass traefik
kubectl -n random-generator get ingress random-generator
```

On Docker Desktop, open [the app](http://app.localhost:8080) and [Grafana](http://grafana.localhost:8080). On Rancher, use the same hostnames without `:8080` and set `GF_SERVER_ROOT_URL` in `k8s-local/manifests/monitoring.yaml` to `http://grafana.localhost` before applying. Grafana login is **admin / admin**. Under **Dashboards → Random Generator**, you will find:

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

If port 80 is refused, check Traefik readiness and Rancher privileged-port permissions. To identify an existing Mac listener, run `lsof -nP -iTCP:80 -sTCP:LISTEN`. On Windows use `Get-NetTCPConnection -LocalPort 8080 -State Listen` in PowerShell. Resolve any conflicting listener yourself; these instructions do not stop existing services. A Traefik 404 usually indicates an unmatched hostname/rule; a 503 usually indicates an unavailable backend. Inspect `kubectl -n random-generator describe ingress random-generator` and pod readiness.

### Windows Docker Desktop: verify from the host first

Run these in **Windows PowerShell**:

```powershell
Test-NetConnection 127.0.0.1 -Port 8080
curl.exe --fail --resolve app.localhost:8080:127.0.0.1 http://app.localhost:8080/
curl.exe --fail --resolve grafana.localhost:8080:127.0.0.1 http://grafana.localhost:8080/api/health
```

Open both URLs in a Windows browser. If explicit resolution works but ordinary hostname resolution fails, add this line using an administrator editor in `C:\Windows\System32\drivers\etc\hosts`:

```text
127.0.0.1 app.localhost grafana.localhost
```

Keep the Ingress hosts and Grafana root URL unchanged. PowerShell requests and Windows browsers use Windows networking and hostname resolution. Do not use a Kubernetes ClusterIP or pod IP for Windows browsers.

Troubleshoot in this order:

- **Refused connection / timeout / pending LoadBalancer:** check Docker Desktop, the Traefik rollout and Service, and Windows port 8080. Use `Get-NetTCPConnection -LocalPort 8080 -State Listen | Select-Object LocalAddress,OwningProcess` in PowerShell, then `Get-Process -Id <PID>`. Inspect `docker ps` for Compose port mappings and check whether Rancher is also running. Resolve a conflicting listener deliberately; do not stop arbitrary processes or reset the cluster. Check firewall/WSL networking if the listener is healthy.
- **Traefik 404:** check the request hostname, `ingressClassName: traefik`, and `web` entrypoint; requesting bare `localhost` does not match either route.
- **502/503:** check ready pods and Service endpoints with `kubectl -n random-generator get endpointslices` and `kubectl -n random-generator describe ingress random-generator`.
- **ImagePullBackOff:** check image architecture/tag, ECR permissions, and the 12-hour token expiry. A controller change cannot fix an image pull.

To isolate controller routing from LoadBalancer forwarding, temporarily run in **Windows PowerShell**:

```powershell
kubectl -n traefik port-forward --address 127.0.0.1 service/traefik 18080:8080
```

In another PowerShell terminal:

```powershell
curl.exe --fail --resolve app.localhost:18080:127.0.0.1 http://app.localhost:18080/api
curl.exe --fail --resolve grafana.localhost:18080:127.0.0.1 http://grafana.localhost:18080/api/health
```

Stop the forward with Ctrl+C. This is diagnostic only (Grafana's configured browser URL uses port 8080). Acceptance requires both Windows browser URLs working on port 8080 **without** a port-forward terminal.

### Check the app, persistence, and metrics

Use the Docker Desktop Ingress application URL below. On macOS/Rancher, use `curl` and omit `:8080`:

```powershell
curl.exe --fail http://app.localhost:8080/
curl.exe --fail http://app.localhost:8080/api
curl.exe --fail http://app.localhost:8080/number
curl.exe --fail http://app.localhost:8080/letter
curl.exe --fail http://app.localhost:8080/rock-paper-scissors
curl.exe --fail http://app.localhost:8080/history
```

Note the history records. Replace the API pod, wait for recovery, and check history again:

```powershell
kubectl -n random-generator delete pod -l app=api
kubectl -n random-generator rollout status deployment/api --timeout=300s
curl.exe --fail http://app.localhost:8080/history
```

Then replace MySQL and verify the same records survive:

```powershell
kubectl -n random-generator delete pod db-0
kubectl -n random-generator rollout status statefulset/db --timeout=300s
kubectl -n random-generator rollout status deployment/api --timeout=300s
curl.exe --fail http://app.localhost:8080/history
```

Pod replacement causes a brief interruption because there is one database replica and the API can scale down to one replica. Allow recovery if the endpoint initially returns 503; inspect the pods if it persists. MySQL history survives pod replacement through its PVC. The previous deployment's data is not copied into this database.

Generate requests and allow at least two Prometheus scrapes for Grafana's charts. To inspect scrape health directly, run a temporary forward in another terminal:

```powershell
kubectl -n random-generator port-forward --address 127.0.0.1 service/prometheus 9090:9090
```

Open `http://localhost:9090/targets`; `random-generator-api` and `mysql` should be UP. In Prometheus, query `mysql_up{job="mysql"}` and confirm it equals `1`. An UP scrape alone does not prove MySQL authentication succeeds. Check all four added dashboards after generating traffic and allowing several scrapes.

The exporter is the second container in `db-0`. It connects to `127.0.0.1:3306` as root using `MYSQL_ROOT_PASSWORD` from the existing `database` Secret. Its HTTP probes check the exporter listener, not MySQL collection. For failures, use `kubectl -n random-generator logs db-0 -c mysql-exporter` and `kubectl -n random-generator logs db-0 -c mysql`. Keep the Secret password matched to the existing database; no new user or database reset is required.

Re-run `kubectl apply -k k8s-local/` and confirm history remains. Prometheus and Grafana storage is temporary, so their history and manual UI changes may disappear after a restart.

## 8. Deploy a newly published latest image

If the ECR token has expired, refresh the existing Secret:

**Windows PowerShell:**

```powershell
$ecrPassword = aws ecr get-login-password --region eu-central-1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ecrPassword)) { throw "ECR authentication failed" }
$secretYaml = kubectl -n random-generator create secret docker-registry ecr-registry --docker-server=834251003876.dkr.ecr.eu-central-1.amazonaws.com --docker-username=AWS --docker-password="$ecrPassword" --dry-run=client -o yaml
if ($LASTEXITCODE -ne 0) { throw "Could not generate ECR Secret" }
$secretYaml | kubectl -n random-generator apply -f -
Remove-Variable ecrPassword -ErrorAction SilentlyContinue
```

**macOS Bash:**

```bash
kubectl -n random-generator create secret docker-registry ecr-registry \
  --docker-server=834251003876.dkr.ecr.eu-central-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region eu-central-1)" \
  --dry-run=client -o yaml |
  kubectl -n random-generator apply -f -
```

To change an image repository or tag, edit `newName` or `newTag` in `k8s-local/kustomization.yaml`, then apply:

```powershell
kubectl apply -k k8s-local/
```

If you published new images under the same `latest` tag, restart both application Deployments:

```powershell
kubectl -n random-generator rollout restart deployment/api deployment/frontend
kubectl -n random-generator rollout status deployment/api --timeout=300s
kubectl -n random-generator rollout status deployment/frontend --timeout=300s
```

`Always` makes each new pod resolve the registry's current `latest` image. Publishing a new tag value alone does not restart existing pods. Ingress access continues to use the same hostnames after rollout.

If monitoring files change, run `kubectl apply -k k8s-local/` again. Kustomize adds content hashes to generated ConfigMap names and updates workload references, triggering monitoring rollouts automatically. Older ConfigMaps remain until namespace cleanup. Database ConfigMap and application Secret changes do not automatically restart pods consuming them through environment variables; restart affected workloads after intentional changes. Changing MySQL passwords also requires updating credentials inside the database.

## 9. Remove the application — destructive

**Only run this when you want to delete the application and all database history in the `random-generator` namespace.** It deletes the namespace and its PVC; the normal local storage provisioner removes the associated data. The local Kubernetes cluster and ingress controller remain running.

```powershell
kubectl delete namespace random-generator --wait=true --timeout=300s
```

Stop port-forward terminals with Ctrl+C. This cleanup does not remove any cluster or AWS resources. If the Docker Desktop controller is no longer needed by any application, remove that Helm release separately:

```powershell
helm uninstall traefik --namespace traefik
```

This removes shared ingress access and is not part of normal application cleanup. Do not run it against Rancher's bundled controller.

## API Horizontal Pod Autoscaler (HPA)

Kustomize now includes an `autoscaling/v2` HPA named `api`. It scales only Deployment `api`, from **1 to 5 replicas**, targeting **70% average CPU utilization**. With a 250m CPU request per API pod, that target is approximately **175m per pod**. CPU requests and limits remain unchanged. Frontend, MySQL, Prometheus, and Grafana remain fixed at one replica.

### Prepare the resource metrics API

The HPA requires metrics-server; Prometheus does not supply this API. Check before installing anything:

```powershell
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl -n kube-system get deployment metrics-server
kubectl top nodes
```

If an existing installation is unhealthy, inspect its logs and APIService rather than installing a duplicate. Rancher normally supplies metrics-server. If **absent on Docker Desktop**, install pinned **v0.9.1**, requiring Kubernetes **1.34+**, per the [upstream compatibility matrix](https://github.com/kubernetes-sigs/metrics-server/tree/v0.9.1#compatibility-matrix). For older servers choose a supported pinned release from that matrix before applying; do not upgrade/reset a cluster implicitly.

```powershell
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.1/components.yaml
kubectl -n kube-system rollout status deployment/metrics-server --timeout=300s
kubectl wait --for=condition=Available apiservice/v1beta1.metrics.k8s.io --timeout=180s
kubectl top nodes
```

If readiness fails, inspect `kubectl -n kube-system logs deployment/metrics-server` and `kubectl describe apiservice v1beta1.metrics.k8s.io`. Only for a **confirmed kubelet serving-certificate validation error** on this local development cluster, edit the Deployment:

```powershell
kubectl -n kube-system edit deployment metrics-server
```

Append `--kubelet-insecure-tls` to the existing metrics-server container `args` without replacing its other arguments. This disables kubelet certificate validation and is for local testing only; do not use it for unrelated network failures or production. Repeat the rollout/APIService/top checks afterwards. Allow several collection cycles before checking HPA CPU values.

The HPA reads the Kubernetes resource metrics API (metrics-server), not Prometheus. Check prerequisites and apply from the repository root:

```powershell
kubectl -n random-generator top pods --containers
kubectl apply -k k8s-local/
kubectl -n random-generator get hpa api
kubectl -n random-generator describe hpa api
```

An initially unknown CPU target can occur until metrics arrive. If it persists, inspect HPA conditions and metrics-server. Refresh the ECR pull Secret using step 8 if its token has expired: newly created API pods must pull the private image. Pending pods can indicate insufficient CPU/memory on the local cluster. Five API replicas request 1.25 CPUs and 2.5 GiB memory in total, in addition to the other workloads. HPA adds pods, not nodes or laptop resources.

Watch autoscaling in one PowerShell or Bash terminal. The optional five-minute load command below requires a separate Bash terminal:

```powershell
kubectl -n random-generator get hpa api -w
```

```bash
bash k8s-local/load-test.sh 100 300
```

Inspect pod count and CPU as needed:

```powershell
kubectl -n random-generator get pods -l app=api
kubectl -n random-generator top pods --containers
kubectl -n random-generator describe hpa api
```

When sustained CPU is above target, expect the desired replica count to rise, up to five. Scale-up allows at most two added pods per 60 seconds. After stopping traffic, scale-down keeps a 120-second stabilization window and removes at most one pod per 60 seconds toward the minimum of one. These are policy limits, not exact timing guarantees; controller sampling and readiness also affect timing.

Verify HPA conditions show valid metrics and scaling activity, new API pods become Ready, and latency improves under the same load. After load stops, verify the count eventually returns to one and application history remains available. A low CPU target under load means HPA may correctly stay at one; inspect frontend, database, and load-generator bottlenecks rather than assuming scaling is broken.

The API manifest intentionally omits `spec.replicas` so later applies do not override HPA decisions. The first apply removing the previously managed replica field can temporarily default it to one; the HPA then controls the count. Reapply once scaling is stable and verify it does not reset replicas.

## Optional Bash load test and autoscaling observation

The existing `load-test.sh` is a Bash script, not a PowerShell script. The commands in this optional section must run in a Bash terminal (macOS, or Git Bash installed separately on Windows), from the repository root. It needs curl and standard shell utilities and does not use Kubernetes credentials or change replicas. Windows deployment, HTTP checks, and HPA inspection above require no Bash. Git Bash load-test behavior has not been validated.

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

Arguments: `workers seconds mode base-url`. The default target is `http://app.localhost` for Rancher. For Docker Desktop, pass port 8080 explicitly, for example `bash k8s-local/load-test.sh 50 120 api http://app.localhost:8080`; use the same fourth argument for `mixed` or `history` mode.

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

```powershell
kubectl -n random-generator get pods -w
```

If the cluster metrics API is available, inspect container CPU:

```powershell
kubectl -n random-generator top pods --containers
```

If `kubectl top` reports metrics unavailable, the HPA cannot calculate CPU utilization. Check `kubectl -n kube-system get deployment metrics-server` and `kubectl -n kube-system logs deployment/metrics-server`; resolve the cluster metrics API before expecting scaling. Prometheus and Grafana do not provide this HPA metric. Watch API latency, errors, request rate, and CPU. Try browsing the app while the load runs. Stop with Ctrl+C and observe recovery.

This generates real load; it does not deliberately freeze a process. Saturation is not guaranteed: the API endpoint is inexpensive, and the client, Ingress, or frontend can bottleneck before the API. These curl workers also consume resources on the same computer as the cluster. Mixed/history modes can bottleneck on the single MySQL pod, which adding API replicas will not fix. Confirm API CPU is the bottleneck and compare identical load parameters against your previous single-pod baseline. The load script does not modify the HPA.

The script has been reviewed as a file but has not been executed or benchmarked on your Mac.

## Validation status

Windows cluster preflight confirmed a Ready AMD64 Docker Desktop node on Kubernetes 1.36.1 and a default StorageClass. Initial Kustomize and Helm rendering passed. During troubleshooting, the app page and Grafana health endpoint returned HTTP 200 through a temporary controller port-forward. Docker Desktop's LoadBalancer could not bind the occupied host port 80. After changing the exposed Service port and Grafana root URL to 8080, the user confirmed the setup works.

The Ingress host rules and backend Service ports remain unchanged. Persistence and HPA/load behavior have not been verified in this session. macOS/Rancher runtime behavior has not been revalidated in this revision.
