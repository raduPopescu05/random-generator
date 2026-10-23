# Random Generator

A Node.js and Express app with a browser UI for generating numbers from 0–99,
uppercase letters, and rock-paper-scissors choices. Each result is stored in
MySQL and displayed in recent history. The backend also exposes health checks
and Prometheus-compatible HTTP, database, generation, and Node.js metrics.

## Quick start with Docker Compose

Install Docker with Compose, then clone the repository:

```sh
git clone https://github.com/raduPopescu05/random-generator.git
cd random-generator
docker compose up -d --build
```

Open [localhost:3000](http://localhost:3000). Compose builds the backend and Nginx
frontend and starts MySQL 8.4. The API waits for MySQL readiness; Nginx waits for
the API. Local builds require no AWS credentials.

Only Nginx is published to the host. It listens on container port 80, the API on
internal port 3000, and MySQL on internal port 3306. To change the host port:

```sh
APP_PORT=8080 docker compose up -d --build
```

`APP_PORT` can also be set in a root-level `.env` file. It controls the Compose
host mapping, not the Node.js listening port.

```sh
docker compose down
```

The `mysql-data` volume preserves history. To also delete that data:

```sh
docker compose down -v
```

## Run directly with Node.js

The project uses Node.js 22 in its Dockerfile and CI. Install Node.js 22 and npm,
and provide a running MySQL server with the database and application user
already created. The application creates its `generations` table on startup.

```sh
npm ci
DB_HOST=127.0.0.1 DB_PORT=3306 DB_NAME=random_generator DB_USER=random_app DB_PASSWORD=your-password npm start
```

These are POSIX shell examples. Set equivalent environment variables when using
PowerShell. The entry point is `src/index.js`; the UI and API are served directly
at [localhost:3000](http://localhost:3000). Startup waits for schema initialization.

| Variable | Direct Node.js default |
| --- | --- |
| `DB_HOST` | `127.0.0.1` |
| `DB_PORT` | `3306` |
| `DB_NAME` | `random_generator` |
| `DB_USER` | `random_app` |
| `DB_PASSWORD` | `random_password` |

Compose supplies its own matching database settings to MySQL and the API.
The Node.js app reads process environment variables; it does not load `.env`
files automatically. Compose does not publish its MySQL port for host access.

## Endpoints

| Method and path | Behavior |
| --- | --- |
| `GET /` | Browser UI |
| `GET /api` | Application information and available generator/history endpoints |
| `GET /number` | Generate and persist an integer from 0–99 |
| `GET /letter` | Generate and persist an uppercase A–Z letter |
| `GET /rock-paper-scissors` | Generate and persist `rock`, `paper`, or `scissors` |
| `GET /history?limit=10` | Recent records, newest first; default limit 20, bounded to 1–100 |
| `GET /health/live` | Backend liveness |
| `GET /health/ready` | Database readiness; HTTP 503 when unavailable |
| `GET /metrics` | Prometheus-compatible metrics |

Generator responses contain `description`, `value`, and `timestamp`. Generation
and history requests return HTTP 503 if persistence is unavailable.

The current Nginx configuration proxies `/api`, the three generator routes, and
`/history`. Health and metrics endpoints are available directly on the backend;
they are not proxied by Nginx. Inside Compose, metrics are at `http://api:3000/metrics`.
Prometheus and Grafana are not included in the Compose stack. Metrics are collected
by `@prometheus-io/client` in `src/utils/metrics.js`.

## Tests and build checks

From the repository root:

```sh
npm ci
npm test
docker compose --env-file /dev/null config --quiet
docker build --check -f docker/backend/Dockerfile .
docker build --check -f docker/frontend/Dockerfile .
docker build -t random-generator-api:check -f docker/backend/Dockerfile .
docker build -t random-generator-web:check -f docker/frontend/Dockerfile .
```

Tests cover generators, date formatting, and metrics using Node's built-in test
runner; they do not require MySQL. Image builds require a running Docker daemon.
Both Dockerfiles use the repository root as their build context.

## CI and image publishing

[GitHub Actions](.github/workflows/ci.yml) runs checks on pushes to `main` and pull
requests targeting `main`. Automatic runs install dependencies, run tests,
validate Compose, and check/build both application images without publishing.

Pushes to `main` automatically install dependencies, run tests, and validate
Compose. After successful checks, the `build-and-publish` job waits for approval
independently for `development` and `preprod`. Approve either or both environments in the
workflow run. Each approved job builds the backend and frontend x64 images
(`linux/amd64`) and pushes them to ECR on the same runner.

No release image is built before approval. Approving both environments runs one
build-and-publish job for each environment. Pull requests still build validation
images automatically and cannot publish. All steps are in `ci.yml`; no image
archives or artifact transfers are needed.

### Configure publication approvals

In **Settings → Environments**, configure `development` and `preprod` with required
reviewers, a deployment branch rule allowing only `main`, and environment secrets
`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Allow self-review if you need to
approve your own runs. Disable administrator bypass if approvals must always be
enforced. A short check before AWS authentication blocks publishing if required
reviewers are missing or the public environment metadata cannot be read.

The GitHub environment `development` supplies approvals and secrets for the
`dev` ECR path. The `preprod` environment uses the `preprod` ECR path.

Images are published under:

```text
834251003876.dkr.ecr.eu-central-1.amazonaws.com/<environment>/random-generator-repository/x64/<backend-or-frontend>:<run-number>
```

Each image also receives `latest`. Publishing is serialized per environment;
an older approved run can move `latest` backward. Use run-number tags for
deployment. The summary reports the commit, environment, build number and image
URIs. CI does not create infrastructure or deploy the application.

Build images for your local machine using `docker compose up -d --build`.
Local builds are separate from the x64-only ECR publishing pipeline.

## AWS deployment order

Follow the [Terraform deployment guide](infrastructure/terraform_wth_modules/README.md):

1. Create repositories locally using the [ECR root](infrastructure/terraform_wth_modules/ecr/README.md).
2. Let CI run checks, then approve building and publishing to the desired environment.
   Use the published `x64` image URIs for the current application AMI.
3. Apply the [application root](infrastructure/terraform_wth_modules/app/README.md) locally with the published image URIs.

The two Terraform roots use separate local state. Application teardown leaves
ECR repositories and images intact. Keep region, account, image architecture,
and the prepared AMI consistent across the stages.

## Repository layout

```text
src/                                  Backend entry point, database, utilities
public/                               Browser UI
test/                                Automated tests
docker/                              Backend, frontend, and Jenkins Dockerfiles
infra-example/                        Independent network and ALB example
infrastructure/
  terraform_wth_modules/
    ecr/                              Repository bootstrap and local state
    app/                              Application infrastructure and local state
  bad_examples/standalone/             Separate standalone Terraform example
docs/                                 Terraform and Jenkins reference guides
.github/workflows/ci.yml               Checks and approved image builds/publication
Jenkinsfile                           Jenkins pipeline
docker-compose.yml                    Local MySQL/API/Nginx stack
```

Further documentation:

- [Network and ALB example](infra-example/README.md)
- [Custom AMI and Terraform reference](docs/terraform.md#required-custom-ami-contract)
- [Jenkins setup](docs/jenkins/setup.md)
- [Jenkins EC2 guide](docs/jenkins/ec2.md)
- [Jenkins pipeline explanation](docs/jenkins/pipeline-explained.md)

The `docs/` files are supplementary references; use the current Terraform
READMEs linked above for deployment paths and execution order.
