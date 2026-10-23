#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Copy development.env.example to development.env and set published image URIs.
# AWS authentication uses your profile or exported credentials.
set -a
source development.env
set +a

: "${AWS_REGION:?Set AWS_REGION in development.env}"
: "${ECR_REGISTRY:?Set ECR_REGISTRY in development.env}"
: "${BACKEND_IMAGE:?Set BACKEND_IMAGE in development.env}"
: "${FRONTEND_IMAGE:?Set FRONTEND_IMAGE in development.env}"
compose=(docker compose -f docker-compose.yml -f docker-compose.ecr.yml)
"${compose[@]}" config --quiet

echo "Logging Docker into $ECR_REGISTRY..."
aws ecr get-login-password --region "$AWS_REGION" |
    docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "Pulling published images..."
"${compose[@]}" pull

echo "Starting services..."
"${compose[@]}" up -d --no-build
"${compose[@]}" ps
