# Local blue/green architecture

## Routing

`app.localhost → Traefik → frontend Service → active frontend → matching API → shared MySQL`

The public Service selects `app: frontend-blue|frontend-green`, `component:
frontend`, and `color: blue|green`. Each color also has its own frontend Service
for port-forward previews. Nginx configuration directs blue to `api-blue:3000`
and green to `api-green:3000`. Distinct app labels prevent legacy selectors from
matching new pods during migration.

## Configuration ownership

The root Kustomization owns shared namespace, database settings, database,
monitoring, and Ingress. It owns neither the public frontend Service nor the
color workloads, so routine shared applies cannot reset routing or images.

Each release directory owns two Deployments, two internal Services, an API HPA,
and a generated Nginx/release ConfigMap. Digest references in that directory
select application images. The ConfigMap hash is injected into the frontend
volume reference; changing its content triggers a rollout.

The public frontend Service is created once during bootstrap and subsequently
changed with manual JSON patches. Each promotion patch tests the expected old
color before replacing the entire selector. The Service is the source of truth
for the active color. The operator records the previous release before switching.

`release.json` is served without caching and records color, release ID, and both
images. It is a manually maintained record: verify it against the actual
Deployment images as described in the runbook.

## Scaling, monitoring, and persistence

Both APIs have independent HPAs using metrics-server, a 70% CPU request target,
and 1–5 replicas. Prometheus independently scrapes both API Services, adding a
release_color label. Service-level scraping does not observe all API pods
individually. Existing dashboards may aggregate both releases.

Both releases use the same database and Secrets. Rollback changes routing and
preserves new records; it cannot undo incompatible schema changes. No automatic
migration or database restore is performed.

## Operational limits

Commands are intentionally manual. A failed check does not prevent an operator
from running a later promotion command; stop on errors. Rollout readiness and
end-to-end preview checks are both required. Keep the previous release running
for manual rollback. Existing connections may briefly remain on the old color.

Follow [DEPLOYMENT.md](DEPLOYMENT.md) for exact commands and failure demonstrations.
