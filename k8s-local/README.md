# Local Kubernetes: blue/green releases

Use the [manual deployment guide](DEPLOYMENT.md) for setup, image selection,
preview, promotion, rollback, monitoring, and cleanup. Run its commands from the
repository root. There is no deployment script.

The existing MySQL database and monitoring are shared. Blue and green each have
a frontend, API, and API HPA. The public frontend Service selects the active color.
Each frontend talks only to its matching API. Releases use exact ECR digests.

- `kubectl apply -k k8s-local/` manages shared infrastructure only.
- `kubectl apply -k k8s-local/releases/blue` manages blue.
- `kubectl apply -k k8s-local/releases/green` manages green.
- Public routing is changed explicitly with the guide’s guarded Service patches.
- Fill in image and release placeholders before applying either color.

See [technical details](tehnical.md) for routing and ownership.
The [legacy setup](LEGACY-SETUP.md) is historical reference, not a deployment guide.
