#!/usr/bin/env bash

# Stop the script as soon as any command fails.
set -e

# Run this script from the repository root after creating development.env.
# development.env must define AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
# AWS_REGION, and ECR_REGISTRY. Keep that file private; it is ignored by Git.
#
# set -a exports variables assigned while sourcing the file so child commands
# such as aws and docker can read the AWS and ECR values.
set -a
source development.env
# Stop automatically exporting variables after development.env is loaded.
set +a

# Get an ECR password from AWS and use it to authenticate Docker.
echo "Logging Docker into $ECR_REGISTRY..."
aws ecr get-login-password --region "$AWS_REGION" |
    docker login --username AWS --password-stdin "$ECR_REGISTRY"

# Pull the backend and frontend latest images configured in docker-compose.yml.
echo "Pulling ECR images..."
docker compose pull

# Start the database, backend, and frontend services in the background.
echo "Starting services..."
docker compose up -d

# Display the current status of the Compose services.
echo "Service status:"
docker compose ps
