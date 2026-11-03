# Manual local blue/green deployment

Run these commands from the repository root, in Bash. No deployment script or
CI deployment job is needed. Both colors share the existing MySQL database.
The public `frontend` Service selects one color; each frontend proxies only to
its own API. Blue and green each have an API HPA (1–5 replicas, CPU target 70%).

## 1. Prepare the cluster and shared services

Required: Rancher Desktop with Kubernetes and Traefik, kubectl, AWS CLI, curl,
and jq. Configure AWS credentials with ECR read/pull access. The supplied ECR
repositories contain ARM images: use repositories matching your node architecture.

```bash
kubectl config use-context rancher-desktop
kubectl config set-context --current --namespace=random-generator
kubectl get nodes -L kubernetes.io/arch
kubectl get storageclass
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes
kubectl apply -f k8s-local/manifests/namespace.yaml
```

Review the database configuration and Secrets locally before applying. For an
existing database, preserve its credentials and PVC; changing initialization
passwords in a Secret does not change passwords stored in an existing MySQL DB.
Do not commit real credentials.

Refresh the image-pull Secret (ECR tokens expire after 12 hours):

```bash
aws ecr get-login-password --region eu-central-1 |
  kubectl create secret docker-registry ecr-registry     --docker-server=834251003876.dkr.ecr.eu-central-1.amazonaws.com     --docker-username=AWS --docker-password="$(cat)"     --dry-run=client -o yaml |
  kubectl apply -f -
kubectl apply -k k8s-local/
kubectl rollout status statefulset/db --timeout=300s
kubectl rollout status deployment/prometheus --timeout=300s
kubectl rollout status deployment/grafana --timeout=300s
```

The root Kustomization now manages only shared resources. Reapplying it does
not change active routing or application release images. Do not apply the old
`manifests/api.yaml`, `frontend.yaml`, or `hpa.yaml`: they are retained as
legacy reference files and are not included in the root Kustomization.
On a new installation, the app URL will not work until step 4 creates its Service.
During migration, the old application continues serving traffic.

## 2. Select exact images for blue

Choose actual numbered tags from your successful image publication. Do not use
`latest`. Frontend and backend tags may differ; record both as one release.

```bash
aws ecr describe-images --region eu-central-1   --repository-name dev/random-generator-repository/arm/backend   --query 'imageDetails[].{tags:imageTags,digest:imageDigest}' --output table
aws ecr describe-images --region eu-central-1   --repository-name dev/random-generator-repository/arm/frontend   --query 'imageDetails[].{tags:imageTags,digest:imageDigest}' --output table
```

Edit `k8s-local/releases/blue/kustomization.yaml`: replace each
`sha256:SET_..._DIGEST` with the corresponding full `sha256:...` digest.
Change `newName` if your repositories differ. Digest pinning prevents a
subsequently moved tag from changing this release.

Edit `k8s-local/releases/blue/release.json` with:
- `color`: `blue`
- `release`: your release ID, for example `release-101`
- `frontend` and `backend`: full `repository@sha256:...` image references,
  matching the Kustomization.

Check that no placeholders remain (no output is expected), inspect, then apply:

```bash
rg 'SET_' k8s-local/releases/blue
kubectl kustomize k8s-local/releases/blue
kubectl apply -k k8s-local/releases/blue
kubectl rollout status deployment/api-blue --timeout=300s
kubectl rollout status deployment/frontend-blue --timeout=300s
kubectl get pods,hpa
```

**Stop if an apply, rollout, or check fails.** Commands are intentionally manual;
later commands are not automatically blocked by earlier failures.
Never edit the active color to deploy a new release.

## 3. Preview blue before sending it public traffic

In a separate terminal:

```bash
kubectl -n random-generator port-forward service/frontend-blue 8081:80
```

In your original terminal:

```bash
curl --fail --show-error http://127.0.0.1:8081/ >/dev/null
curl --fail --show-error http://127.0.0.1:8081/api
curl --fail --show-error http://127.0.0.1:8081/history
curl --fail --show-error http://127.0.0.1:8081/release.json | jq .
curl --fail --silent http://127.0.0.1:8081/release.json |
  jq -e --slurpfile expected k8s-local/releases/blue/release.json '. == $expected[0]'
kubectl get deployment api-blue frontend-blue   -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

Verify the image references match the marker. Open http://127.0.0.1:8081 in a
browser and generate a record. The history should include it. Stop port-forward
with Ctrl+C when done. During a failed preview, leave public routing unchanged.

## 4. Bootstrap public routing, then retire the legacy app

Only after blue passes every check, run this once. This creates the public
Service on a new installation or updates it during migration:

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: random-generator
spec:
  selector:
    app: frontend-blue
    component: frontend
    color: blue
  ports:
    - port: 80
      targetPort: http
YAML
curl --fail --show-error http://app.localhost/release.json | jq -e '.color == "blue"'
curl --fail --show-error http://app.localhost/api
curl --fail --show-error http://app.localhost/history
```

If migrating and the public checks fail, keep the legacy deployments and restore
their original routing:

```bash
kubectl patch service frontend --type=json   -p='[{"op":"replace","path":"/spec/selector","value":{"app":"frontend"}}]'
```

After successful public checks, retire only the old application resources:

```bash
kubectl delete hpa api --ignore-not-found
kubectl delete deployment frontend api --ignore-not-found
kubectl delete service api --ignore-not-found
```

Do not delete MySQL, its PVC, the namespace, or monitoring resources.
Blue/green pods use distinct `app` labels, so the legacy Service cannot
accidentally send traffic to partially initialized new pods before promotion.

Initialize green with the same known working image digests and release ID:
edit its Kustomization and marker as in step 2, keeping `color: green`.
Apply it and perform step 3 with `green` instead of `blue`.

```bash
kubectl apply -k k8s-local/releases/green
kubectl rollout status deployment/api-green --timeout=300s
kubectl rollout status deployment/frontend-green --timeout=300s
```

## 5. Deploy the next release into the inactive color

Find the active color first:

```bash
kubectl get service frontend -o jsonpath='{.spec.selector.color}{"\n"}'
```

If it says blue, prepare green with the new release ID and exact image digests.
If it says green, prepare blue. Record the retained release before overwriting it;
replacing the inactive color removes that older rollback candidate.

Apply only that color and repeat the rollout, image, marker, UI, API, and history
checks from steps 2–3. Requests to `app.localhost` must still show the old release.
Generated ConfigMap hashes trigger a frontend rollout when Nginx configuration
or the release marker changes. API replica counts remain managed by HPA.

## 6. Promote green and observe

The following example assumes blue is active and green passed all checks.
Record blue's release and images before switching. Do not run release operations
concurrently in multiple terminals.

```bash
kubectl get service frontend -o jsonpath='{.spec.selector}{"\n"}'
kubectl get deployment api-blue frontend-blue   -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
kubectl patch service frontend --type=json -p='[
  {"op":"test","path":"/spec/selector/color","value":"blue"},
  {"op":"replace","path":"/spec/selector","value":{"app":"frontend-green","component":"frontend","color":"green"}}
]'
curl --fail --show-error http://app.localhost/release.json | jq -e '.color == "green"'
curl --fail --show-error http://app.localhost/api
curl --fail --show-error http://app.localhost/history
```

The JSON patch refuses to switch if blue is no longer active. For the opposite
direction, exchange blue and green in the commands. Allow a short period for
Service endpoint propagation; existing connections may finish on the old release.

For ten minutes, repeatedly check the public UI, API, database history, and
release marker. This optional terminal loop performs 60 checks approximately ten
seconds apart (request time adds to the total); it does not deploy or roll back:

```bash
for attempt in $(seq 1 60); do
  if ! curl --fail --silent --show-error --max-time 5 http://app.localhost/ >/dev/null ||
     ! curl --fail --silent --show-error --max-time 5 http://app.localhost/api >/dev/null ||
     ! curl --fail --silent --show-error --max-time 5 http://app.localhost/history >/dev/null ||
     ! curl --fail --silent --show-error --max-time 5 http://app.localhost/release.json |
       jq -e '.color == "green"' >/dev/null; then
    echo "Health check failed: inspect the release and use step 7 to roll back."
    break
  fi
  date
  sleep 10
done
```

Keep blue running throughout observation and until you intentionally replace it.

## 7. Roll back green to blue

First preview blue again and confirm its Deployments are ready. Then:

```bash
kubectl rollout status deployment/api-blue --timeout=300s
kubectl rollout status deployment/frontend-blue --timeout=300s
kubectl patch service frontend --type=json -p='[
  {"op":"test","path":"/spec/selector/color","value":"green"},
  {"op":"replace","path":"/spec/selector","value":{"app":"frontend-blue","component":"frontend","color":"blue"}}
]'
curl --fail --show-error http://app.localhost/release.json | jq -e '.color == "blue"'
curl --fail --show-error http://app.localhost/api
curl --fail --show-error http://app.localhost/history
```

Confirm records created while green was active remain in history. Rollback
changes application routing; it does not restore a database backup or undo writes.
Both releases must support the shared schema. Destructive schema changes need a
separate migration and recovery procedure.

## 8. Status, monitoring, and failure demonstration

```bash
kubectl get service frontend -o jsonpath='{.spec.selector.color}{"\n"}'
kubectl get deployments,pods,hpa
kubectl describe hpa api-blue
kubectl describe hpa api-green
kubectl top pods
curl --fail --show-error http://app.localhost/release.json | jq .
```

Prometheus scrapes both API Services with `release_color=blue|green`. Confirm
both targets are UP. Existing dashboards may aggregate both colors; filter by
`release_color` in Explore when comparing releases. These are Service-level
scrapes, not discovery of every replica. The HPA reads metrics-server independently.

For an invalid-image demo, use only the inactive color. First record its working
image, then deliberately set an image with a nonexistent tag:

```bash
# Only when blue is active:
kubectl get service frontend -o jsonpath='{.spec.selector.color}{"\n"}'
kubectl set image deployment/api-green api=example.invalid/demo:missing
kubectl rollout status deployment/api-green --timeout=60s
kubectl describe pods -l app=api-green
curl --fail --show-error http://app.localhost/release.json | jq -e '.color == "blue"'
# Restore the declared working release, then repeat preview checks:
kubectl apply -k k8s-local/releases/green
kubectl rollout status deployment/api-green --timeout=300s
```

To demonstrate failed readiness instead, patch only the inactive API:

```bash
kubectl patch deployment api-green --type=json   -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/deliberately-missing-health"}]'
kubectl rollout status deployment/api-green --timeout=60s
# Expect timeout; do not promote. Restore and recheck:
kubectl apply -k k8s-local/releases/green
kubectl rollout status deployment/api-green --timeout=300s
```

Because promotion is manual, you must stop when checks fail. There is no script
enforcing that decision. A healthy old replica may still answer while a rollout
is failing, so successful curl alone is insufficient: rollout status must pass.

## 9. Troubleshooting and cleanup

- ImagePullBackOff: refresh ECR credentials, verify digest and node architecture.
- Pending pods: inspect events and laptop resource allocation. Ten API replicas
  request 2.5 CPU and 5 GiB memory; two frontends add 0.5 CPU and 1 GiB, before
  database, monitoring, and Kubernetes overhead.
- Unknown HPA CPU: inspect metrics-server and `kubectl top pods`.
- Wrong release marker: inspect public Service selector, Deployment images, and
  frontend rollout; do not assume editing the marker changed the image.
- App hostname fails: check Traefik, local port 80, and hostname resolution.
- Interrupted bootstrap: inspect resources and resume the failed step; do not
  delete the database or rerun routing commands blindly.

To remove just the color workloads (this interrupts application service):

```bash
kubectl delete -k k8s-local/releases/blue
kubectl delete -k k8s-local/releases/green
kubectl delete service frontend
```

Generated ConfigMaps from older releases may remain. Inspect them and remove only
ones no longer referenced by a Deployment or retained ReplicaSet. Do not delete
the namespace or database PVC unless you intend to destroy application data.
