# Kubernetes Networking and Configuration: Ingress, Helm, and Kustomize

This guide explains the tools and concepts used by the local deployment: **Ingress** for routing incoming web traffic, **Helm** for installing and managing Traefik on Docker Desktop, and **Kustomize** for assembling application manifests. The examples refer to the `random-generator` namespace and files in `k8s-local/`.

## Ingress: routing web requests into the cluster

An **Ingress** is a Kubernetes API resource that describes how HTTP or HTTPS requests should be routed to Services inside a cluster. It commonly matches a request by hostname and URL path. The Ingress resource is a set of routing rules; it is not itself a web server, load balancer, or proxy that accepts connections.

An **Ingress controller** watches Ingress resources and implements their rules. This local deployment uses **Traefik** as its controller. Traefik receives browser traffic through HTTP port 8080 on Docker Desktop (port 80 with Rancher's bundled setup), looks at the request host, finds the matching Ingress rule, and forwards the request to the specified Service. The Service then sends it to a ready Pod selected by its labels.

The route can be viewed as:

```text
Browser → Traefik (Ingress controller) → Ingress rule → Service → Pod
```

### Routes in this deployment

The rules are defined in [`manifests/ingress.yaml`](manifests/ingress.yaml). The resource is named `random-generator`, is in the `random-generator` namespace, and selects the `traefik` Ingress class. Its two hostname rules are:

| Browser request | Ingress backend | What serves the request |
| --- | --- | --- |
| `http://app.localhost:8080/` | Service `frontend`, port 80 | The frontend Pod serves the web UI. Its application API requests are handled through the frontend/API setup. |
| `http://grafana.localhost:8080/` | Service `grafana`, port 3000 | The Grafana Pod serves the monitoring UI. |

Both rules use the `/` path with `pathType: Prefix`, so they match the root path and paths below it for their respective hostname. The hostname is what distinguishes the two sites when both use the same HTTP port. The Services are internal `ClusterIP` Services; Traefik provides the external entry point.

Creating an Ingress resource alone does not make it work: a compatible controller must be installed and running, and it must handle the resource's Ingress class. On Docker Desktop, install Traefik with Helm as described below. On Rancher Desktop, enable its bundled Traefik controller instead. The `traefik.ingress.kubernetes.io/router.entrypoints: web` annotation selects Traefik's `web` entry point for these routes.

If a hostname does not resolve to the local cluster's reachable address, the browser cannot reach Traefik even if the Ingress rules are correct. The local README describes checking Traefik and hostname resolution from Windows PowerShell or macOS. The URLs above use Docker Desktop's port 8080. For Rancher, omit `:8080` and set Grafana's `GF_SERVER_ROOT_URL` to `http://grafana.localhost` before applying.

## Helm: installing and managing Kubernetes packages

**Helm** is a package manager for Kubernetes. It helps install and update software that needs several related resources, such as a Deployment, Service, and permissions.

Three terms explain the workflow:

- **Chart:** a versioned package containing Kubernetes resource templates and default configuration.
- **Values:** configuration supplied to the templates, usually in a YAML file. Overrides let you customize the package without editing its templates.
- **Release:** a named installation of a chart in a cluster. Helm tracks revisions so you can inspect installation history and roll back resource configuration.

Helm combines a chart with values to render Kubernetes manifests, then submits them to Kubernetes during installation or upgrade. Chart versions and application versions are separate: updating a chart can change its templates as well as its default application image. See the [official chart documentation](https://helm.sh/docs/topics/charts/).

### How this project uses Helm

Docker Desktop needs an explicit installation of the Traefik controller. We use the upstream `traefik/traefik` chart, with release name `traefik` in namespace `traefik`. Chart version `42.3.0` selects Traefik `v3.7.17` by default. These are also distinct from the version of the Helm CLI installed through Chocolatey.

Our [`traefik-values.yaml`](traefik-values.yaml) configures one controller replica, the `traefik` IngressClass, the Kubernetes Ingress provider, and a LoadBalancer Service exposing port **8080**. It disables the dashboard. The file is Helm input, not a Kubernetes resource: use it with Helm's `-f` option, not `kubectl apply -f`.

From the repository root in PowerShell:

```powershell
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik
helm upgrade --install traefik traefik/traefik --version 42.3.0 --namespace traefik --create-namespace -f k8s-local/traefik-values.yaml --wait --timeout 300s
```

Here, `upgrade --install` updates the named release if it exists, or installs it otherwise. `--version` pins the chart; `--namespace` selects the release namespace; `-f` supplies our overrides. `--wait` waits for supported resource readiness checks, but does not prove browser access or application functionality.

Inspect the release or preview its manifests without changing the cluster:

```powershell
helm list -n traefik
helm status traefik -n traefik
helm history traefik -n traefik
helm template traefik traefik/traefik --version 42.3.0 --namespace traefik --kube-version 1.36.1 -f k8s-local/traefik-values.yaml
```

Use your server version for `--kube-version` when rendering. After editing the values file, repeat the upgrade command to apply it; editing the file alone does not change the running controller. For example, changing `ports.web.exposedPort` changes the controller Service's published port. The current route is Windows port 8080 → Traefik Service port 8080 → Traefik's internal `web` port 8000. Backend ports remain frontend 80 and Grafana 3000.

### Helm and Kustomize in this repository

Helm manages the external Traefik package. Kustomize manages our application, database, monitoring, and Ingress rules. Running `kubectl apply -k k8s-local/` does not install or upgrade the Helm release, and upgrading Traefik does not deploy our application. Rancher's bundled controller replaces the Helm installation step on macOS. See [`README.md`](README.md) for installation prerequisites and cleanup commands.

## Kustomize: assembling Kubernetes manifests

**Kustomize** is a configuration management tool for Kubernetes resources. It takes YAML manifests as input, combines and transforms them, and produces a final set of Kubernetes objects. The input files remain ordinary Kubernetes YAML; Kustomize applies changes at deploy time without requiring template expressions inside those files.

Kustomize is included with `kubectl`, so this repository uses commands such as:

```bash
# Inspect the rendered resources without applying them
kubectl kustomize k8s-local/

# Build and apply the Kustomize configuration
kubectl apply -k k8s-local/
```

The `-k` option tells `kubectl` to treat the path as a Kustomize directory. This is different from `kubectl apply -f`, which applies files directly and does not perform this directory's image substitutions or generated ConfigMaps.

### The Kustomization file

[`kustomization.yaml`](kustomization.yaml) is the configuration entry point. It tells Kustomize which resources to include and which transformations or generators to apply. In this directory it:

- Includes the namespace, application configuration, Secret, database, API, HPA, frontend, monitoring, and Ingress manifests.
- Sets `namespace: random-generator` for namespaced resources.
- Replaces placeholder image names such as `backend-image` and `frontend-image` with concrete image repositories and tags. It also selects images for MySQL, its exporter, Prometheus, and Grafana.
- Generates ConfigMaps from monitoring configuration and dashboard files under `k8s-local/monitoring/`.

### Image substitutions

Workload manifests use readable placeholder image references, for example `image: backend-image` in `manifests/api.yaml`. The `images` section in `kustomization.yaml` maps that name to a real image repository and tag. Kustomize rewrites the image in the rendered output before `kubectl` sends the Deployment to Kubernetes.

To change which image is deployed, edit the corresponding `newName` or `newTag` in `kustomization.yaml`, then render or apply the directory with Kustomize. Applying the workload YAML directly with `-f` would bypass these substitutions, leaving the placeholder image unresolved.

### Generated ConfigMaps

The `configMapGenerator` section builds ConfigMaps from files such as `monitoring/prometheus.yml`, Grafana datasource and provider settings, and dashboard JSON. This keeps those settings in normal files while making them available to Pods as Kubernetes ConfigMaps.

By default, generated ConfigMap names include a hash of their contents. Kustomize updates references to those generated ConfigMaps in the rendered workloads. When a source file changes and the configuration is applied again, the changed name prompts Kubernetes to update the workloads that consume it. This behavior is used for the Prometheus and Grafana configuration in this deployment.

### Composition and overlays

Kustomize's `resources` list composes several resource files into one deployable configuration. For larger setups, a common pattern is to keep shared resources in a base and create overlays for environments such as development, staging, and production. An overlay references the base and applies environment-specific image, replica, namespace, or configuration changes.

This repository's `k8s-local/` directory is a directly applicable Kustomize configuration rather than a base-and-overlay hierarchy. The concepts still apply: the Kustomization file gathers resources and makes consistent changes across them before application.

Kustomize prepares the desired resource definitions; it does not wait for Pods to become ready or guarantee that dependencies start in order. After applying, use Kubernetes rollout and pod status commands to check that workloads are healthy. See [`README.md`](README.md) for the full local deployment procedure.

## How the pieces work together

For this deployment, Kustomize assembles the Kubernetes resources and applies the configured images, namespace, and generated monitoring ConfigMaps. Kubernetes then creates the Services, Deployments, database, monitoring components, and Ingress resource in the cluster. Traefik watches the Ingress resource and routes browser requests for `app.localhost` and `grafana.localhost` to their respective internal Services.

Helm installs and updates Traefik on Docker Desktop; Kustomize prepares application resources for kubectl to apply; Ingress describes web routing; Traefik implements those routes. To make a change, edit the relevant manifest or source configuration, render it with `kubectl kustomize k8s-local/` if you want to inspect the result, and apply it with `kubectl apply -k k8s-local/`.
