# Kubernetes Networking and Configuration: Ingress and Kustomize

This guide explains the two Kubernetes concepts used by the local deployment in this directory: **Ingress** for routing incoming web traffic, and **Kustomize** for assembling and customizing Kubernetes resource manifests. The examples refer to the `random-generator` namespace and files in `k8s-local/`.

## Ingress: routing web requests into the cluster

An **Ingress** is a Kubernetes API resource that describes how HTTP or HTTPS requests should be routed to Services inside a cluster. It commonly matches a request by hostname and URL path. The Ingress resource is a set of routing rules; it is not itself a web server, load balancer, or proxy that accepts connections.

An **Ingress controller** watches Ingress resources and implements their rules. This local deployment uses **Traefik** as its controller. Traefik receives browser traffic on HTTP port 80, looks at the request host, finds the matching Ingress rule, and forwards the request to the specified Service. The Service then sends it to a ready Pod selected by its labels.

The route can be viewed as:

```text
Browser → Traefik (Ingress controller) → Ingress rule → Service → Pod
```

### Routes in this deployment

The rules are defined in [`manifests/ingress.yaml`](manifests/ingress.yaml). The resource is named `random-generator`, is in the `random-generator` namespace, and selects the `traefik` Ingress class. Its two hostname rules are:

| Browser request | Ingress backend | What serves the request |
| --- | --- | --- |
| `http://app.localhost/` | Service `frontend`, port 80 | The frontend Pod serves the web UI. Its application API requests are handled through the frontend/API setup. |
| `http://grafana.localhost/` | Service `grafana`, port 3000 | The Grafana Pod serves the monitoring UI. |

Both rules use the `/` path with `pathType: Prefix`, so they match the root path and paths below it for their respective hostname. The hostname is what distinguishes the two sites when both use the same HTTP port. The Services are internal `ClusterIP` Services; Traefik provides the external entry point.

Creating an Ingress resource alone does not make it work: a compatible controller must be installed and running, and it must handle the resource's Ingress class. For this setup, Rancher Desktop must have Kubernetes and Traefik enabled. The `traefik.ingress.kubernetes.io/router.entrypoints: web` annotation selects Traefik's `web` entry point for these routes.

If a hostname does not resolve to the local cluster's reachable address, the browser cannot reach Traefik even if the Ingress rules are correct. The local README describes checking Traefik, port 80, and hostname resolution for Mac and Windows/WSL.

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

In short, Kustomize prepares and applies the cluster configuration; Ingress describes web routing; Traefik implements those routes. To make a change, edit the relevant manifest or source configuration, render it with `kubectl kustomize k8s-local/` if you want to inspect the result, and apply it with `kubectl apply -k k8s-local/`.
