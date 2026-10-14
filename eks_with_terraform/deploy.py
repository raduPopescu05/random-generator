#!/usr/bin/env python3
"""Deploy or remove the EKS application using the last applied Terraform outputs.

Uses only Python's standard library and the installed terraform/aws/kubectl/helm
CLIs. This script never runs terraform apply or terraform destroy.
"""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent
NAMESPACE = "random-generator"
RELEASE = "aws-load-balancer-controller"
CHART_VERSION = "1.14.1"
REQUIRED_OUTPUTS = (
    "cluster_name", "region", "vpc_id", "controller_role_arn",
    "backend_image", "frontend_image",
)


class DeploymentError(Exception):
    pass


def command(args, *, env=None, input_text=None, show=False, sensitive=False):
    """Never invoke a shell or log input data (which may contain a Secret)."""
    try:
        result = subprocess.run(
            args, cwd=ROOT, env=env, input=input_text, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=1800,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise DeploymentError(f"Could not run {args[0]}: {exc}") from exc
    if result.returncode:
        details = "Sensitive command output withheld." if sensitive else result.stderr.strip()
        raise DeploymentError(f"Command failed: {' '.join(args)}\n{details}")
    if show and result.stdout.strip():
        print(result.stdout.strip(), flush=True)
    return result.stdout


def wait_until(description, probe, timeout=600):
    print(f"Waiting for {description}...", flush=True)
    deadline = time.monotonic() + timeout
    while True:
        value = probe()
        if value:
            return value
        if time.monotonic() >= deadline:
            raise DeploymentError(f"Timed out waiting for {description}. Fix the cause and rerun this command.")
        time.sleep(5)


def load_config(require_current=True):
    local_file = ROOT / "terraform.tfvars.json"
    if require_current and not local_file.exists():
        raise DeploymentError("Copy terraform.tfvars.json.example to terraform.tfvars.json and configure it first.")
    if require_current and (ROOT / "terraform.tfvars").exists():
        raise DeploymentError("Move the old terraform.tfvars into .local/ after migrating its settings to terraform.tfvars.json.")
    local = json.loads(local_file.read_text()) if require_current else {}
    raw = command(["terraform", "output", "-json", "deployment_config"])
    config = json.loads(raw)
    if not isinstance(config, dict) or any(not config.get(key) for key in REQUIRED_OUTPUTS):
        raise DeploymentError("Deployment outputs are missing. Run terraform apply in eks_with_terraform first.")
    # Avoid silently deploying old image tags/settings after the user edits config.
    for key in (*REQUIRED_OUTPUTS, "aws_profile"):
        if key in local and local[key] != config.get(key):
            raise DeploymentError(f"{key} differs from applied Terraform outputs. Run terraform apply first.")
    return config


def render_text(text, substitutions):
    for key, value in substitutions.items():
        text = text.replace(f'"__{key}__"', json.dumps(value))
    if re.search(r'"__[A-Z_]+__"', text):
        raise DeploymentError("An unresolved configuration placeholder remains in a manifest.")
    return text


class Deployment:
    def __init__(self, config):
        self.config = config
        self.local = ROOT / ".local"
        self.local.mkdir(mode=0o700, exist_ok=True)
        self.env = os.environ.copy()
        if config.get("aws_profile"):
            self.env["AWS_PROFILE"] = config["aws_profile"]
        self.env["AWS_REGION"] = config["region"]
        self.env["AWS_DEFAULT_REGION"] = config["region"]
        self.env["AWS_PAGER"] = ""
        # Never alter the user's default kubeconfig or selected context.
        self.env["KUBECONFIG"] = str(self.local / "kubeconfig")

    def run(self, args, **kwargs):
        return command(args, env=self.env, **kwargs)

    def kube(self, *args, **kwargs):
        return self.run(["kubectl", *args], **kwargs)

    def aws(self, *args):
        return json.loads(self.run(["aws", *args, "--region", self.config["region"], "--output", "json"]))

    def connect(self):
        print(f"Target: {self.config['cluster_name']} ({self.config['region']})", flush=True)
        self.run([
            "aws", "eks", "update-kubeconfig", "--region", self.config["region"],
            "--name", self.config["cluster_name"], "--kubeconfig", self.env["KUBECONFIG"],
            "--alias", self.config["cluster_name"],
        ])
        os.chmod(self.env["KUBECONFIG"], 0o600)
        allowed = self.kube("auth", "can-i", "create", "deployments", "-n", NAMESPACE).strip()
        if allowed != "yes":
            raise DeploymentError("The active AWS identity cannot deploy. Check aws_profile and admin_principal_arn.")

    def render(self):
        rendered = self.local / "rendered"
        rendered.mkdir(exist_ok=True)
        substitutions = {
            "CLUSTER_NAME": self.config["cluster_name"], "REGION": self.config["region"],
            "VPC_ID": self.config["vpc_id"], "CONTROLLER_ROLE_ARN": self.config["controller_role_arn"],
            "BACKEND_IMAGE": self.config["backend_image"], "FRONTEND_IMAGE": self.config["frontend_image"],
        }
        for path in (ROOT / "kubernetes").glob("*.yaml"):
            (rendered / path.name).write_text(render_text(path.read_text(), substitutions))
        values = ROOT / "platform" / "controller-values.example.yaml"
        (self.local / "controller-values.yaml").write_text(render_text(values.read_text(), substitutions))
        return rendered

    def apply(self, path):
        self.kube("apply", "-f", str(path), show=True)

    def rollout(self, name, namespace=NAMESPACE):
        print(f"Waiting for {namespace}/{name} rollout...", flush=True)
        self.kube("-n", namespace, "rollout", "status", f"deployment/{name}", "--timeout=15m", show=True)

    def ensure_secret(self):
        existing = self.kube("-n", NAMESPACE, "get", "secret", "app-db", "--ignore-not-found", "-o", "json", sensitive=True)
        if existing.strip():
            data = json.loads(existing).get("data", {})
            if not all(data.get(key) for key in ("DB_PASSWORD", "DB_ROOT_PASSWORD")):
                raise DeploymentError("Existing app-db Secret lacks required passwords; repair it without rotating an initialized DB.")
            print("Reusing existing database credentials.", flush=True)
            return
        secret = {
            "apiVersion": "v1", "kind": "Secret", "type": "Opaque",
            "metadata": {"name": "app-db", "namespace": NAMESPACE},
            "stringData": {key: secrets.token_urlsafe(24) for key in ("DB_PASSWORD", "DB_ROOT_PASSWORD")},
        }
        # create (not apply) avoids overwriting a Secret another process just made,
        # and avoids storing a second plaintext copy in an apply annotation.
        self.kube("create", "-f", "-", input_text=json.dumps(secret), sensitive=True)
        print("Created development database credentials in Kubernetes.", flush=True)

    def ingress_host(self):
        raw = self.kube("-n", NAMESPACE, "get", "ingress", "random-generator", "--ignore-not-found", "-o", "json")
        if not raw.strip():
            return None
        entries = json.loads(raw).get("status", {}).get("loadBalancer", {}).get("ingress", [])
        return next((entry["hostname"] for entry in entries if entry.get("hostname")), None)

    @staticmethod
    def healthy(url):
        try:
            for path in ("/health/ready", "/history?limit=1"):
                with urllib.request.urlopen(url + path, timeout=10) as response:
                    body = json.load(response)
                    if response.status != 200:
                        return False
                    if path.startswith("/history") and (not isinstance(body, dict) or not isinstance(body.get("generations"), list)):
                        return False
            return True
        except (urllib.error.URLError, OSError, ValueError):
            return False

    def up(self):
        rendered = self.render()
        print("Configuring CoreDNS for Fargate...", flush=True)
        self.kube("-n", "kube-system", "patch", "deployment", "coredns", "--type=strategic",
                  "--patch-file=" + str(ROOT / "platform" / "coredns-patch.yaml"), show=True)
        self.rollout("coredns", "kube-system")
        print(f"Installing controller chart {CHART_VERSION}...", flush=True)
        self.run([
            "helm", "upgrade", "--install", RELEASE, RELEASE, "--repo", "https://aws.github.io/eks-charts",
            "--version", CHART_VERSION, "--namespace", "kube-system", "--values",
            str(self.local / "controller-values.yaml"), "--wait", "--timeout", "15m",
        ], show=True)
        self.rollout(RELEASE, "kube-system")
        self.apply(rendered / "00-namespace.yaml")
        self.ensure_secret()
        for name in ("01-config.yaml", "02-nginx.yaml", "10-mysql.yaml"):
            self.apply(rendered / name)
        self.rollout("db")
        for name, filename in (("api", "20-backend.yaml"), ("web", "30-frontend.yaml")):
            self.apply(rendered / filename)
            # Refresh mutable tags and mounted config; API startup also restores
            # the schema if the disposable MySQL pod has been replaced.
            self.kube("-n", NAMESPACE, "rollout", "restart", f"deployment/{name}")
            self.rollout(name)
        self.apply(rendered / "40-ingress.yaml")
        hostname = wait_until("the ALB hostname", self.ingress_host)
        if not re.fullmatch(r"[A-Za-z0-9.-]+\.elb\.amazonaws\.com", hostname):
            raise DeploymentError("Ingress returned an unexpected ALB hostname; inspect its status.")
        url = f"http://{hostname}"
        wait_until("ALB readiness and database schema", lambda: self.healthy(url))
        print(f"\nApplication ready: {url}", flush=True)

    def controller_resources(self):
        # Includes orphaned resources when an Ingress has already disappeared.
        return self.aws(
            "resourcegroupstaggingapi", "get-resources", "--tag-filters",
            f"Key=elbv2.k8s.aws/cluster,Values={self.config['cluster_name']}",
            "--resource-type-filters", "elasticloadbalancing:loadbalancer",
            "elasticloadbalancing:targetgroup", "ec2:security-group",
        ).get("ResourceTagMappingList", [])

    def down(self):
        # Refuse to remove a controller serving other applications.
        ingresses = json.loads(self.kube("get", "ingress", "--all-namespaces", "-o", "json"))["items"]
        others = [item for item in ingresses if item.get("spec", {}).get("ingressClassName") == "alb"
                  and (item["metadata"]["namespace"], item["metadata"]["name"]) != (NAMESPACE, "random-generator")]
        if others:
            raise DeploymentError("Other ALB Ingresses exist. Remove them before uninstalling the shared controller.")
        # Check permission before changing anything; IAM/network errors must not
        # be interpreted as proof that AWS resources have been removed.
        self.controller_resources()
        print("Removing application Ingress while its controller is running...", flush=True)
        self.kube("-n", NAMESPACE, "delete", "ingress", "random-generator", "--ignore-not-found",
                  "--wait=true", "--timeout=10m", show=True)
        wait_until("controller-created AWS resources to be removed", lambda: not self.controller_resources())
        self.kube("delete", "namespace", NAMESPACE, "--ignore-not-found", "--wait=true", "--timeout=10m", show=True)
        releases = json.loads(self.run(["helm", "list", "--namespace", "kube-system", "--all", "--output", "json"]))
        if any(release["name"] == RELEASE for release in releases):
            self.run(["helm", "uninstall", RELEASE, "--namespace", "kube-system", "--wait", "--timeout", "10m"], show=True)
        print("\nApplication cleanup complete. You can now run: terraform destroy", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", nargs="?", choices=("up", "down"), default="up",
                        help="up deploys/updates the app; down removes it before terraform destroy")
    args = parser.parse_args()
    try:
        for tool in ("terraform", "aws", "kubectl", "helm"):
            if not shutil.which(tool):
                raise DeploymentError(f"Install {tool} and make it available on PATH first.")
        deployment = Deployment(load_config(require_current=args.action == "up"))
        deployment.connect()
        getattr(deployment, args.action)()
    except (DeploymentError, ValueError, OSError) as exc:
        print(f"\nError: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nInterrupted. Existing resources were retained; rerun after checking their status.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
