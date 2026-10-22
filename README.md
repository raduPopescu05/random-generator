# RANDOM GENERATOR 
A simple Node.js and Express application that exposes API endpoints for generating random numbers and letters.

## Features
- Returns basic application information
- Generates a random number between 0 and 99
- Generates a random uppercase letter from A to Z
- Returns responses in JSON format

## Requirements
- Node.js 22 or 24 (or version 26+), when running outside Docker
- npm

## Installation
Clone the repository: 
````
git clone git@github.com:Adrian-Moldovan/nodejs-random-generator.git
cd <repository-folder>
````

Install the dependencies:
````
npm install
````

## Running the Application
Start the server with: 
````
npm start
````

When starting Node directly, MySQL must already be running and the `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, and `DB_PASSWORD` environment variables must point to it. For the complete local setup, use Docker Compose below.

The API will run at:
````
http://localhost:3000
````

## Running with Docker

Build the image and start the container:
````
docker build -t random-generator .
docker run --rm -p 3000:3000 random-generator
````

Open `http://localhost:3000` for the UI. The API endpoints remain available at `/number`, `/letter`, and `/rock-paper-scissors`.

To stop the container, press `Ctrl+C`.

### Docker Compose

Start the app with:
````
docker compose up -d --build
````

This builds the API and Nginx frontend locally and starts three services: MySQL,
the API, and the frontend. No ECR login or monitoring credentials are needed.
MySQL is available internally as `db:3306`; `mysql-data` preserves its data.
Open `http://localhost:3000` for the app. Set `APP_PORT` to use a different host port
(for example, `APP_PORT=8080 docker compose up -d --build`).

`APP_PORT` is an optional Compose variable supplied by your shell or a `.env` file
in the repository root (for example, `APP_PORT=8080`). It is not defined in app
code. The `${APP_PORT:-3000}` expression in Compose defaults to `3000` when the
variable is unset or empty. This lets you avoid a host-port conflict without
editing Compose; the frontend still listens on port 80 and the API on port 3000
inside their containers. With the example above, open `http://localhost:8080`.

The original ECR image URLs are kept as comments beside each local build setting.
To use those prebuilt images, uncomment the `image` lines and remove or comment
out each service's complete `build` setting, then authenticate to ECR and pull
the images before starting Compose.

The API waits for the MySQL health check before starting, and the web service waits
for the API health check.

Stop the app with:
````
docker compose down
````

To also remove the database volume and its generation history:
````
docker compose down -v
````

### Adding monitoring later

The API already collects HTTP, generation, database, and Node.js runtime metrics.
It exposes them at `http://api:3000/metrics` inside the Compose network, and runs
normally without a metrics collector. Nginx does not proxy this endpoint publicly.

To add monitoring later, add Prometheus and Grafana services to Compose and supply
their configuration files. Configure Prometheus on the same Compose network to
scrape `api:3000` at `/metrics`, then configure Grafana to use Prometheus as its
data source. No app-code changes are required. Metric names and labels remain
compatible with the dashboards on the `monitoring` branch.

### Metrics dependencies

`@prometheus-io/client` is a direct app dependency used by `utils/metrics.js` to
create counters, duration histograms, default Node.js/process metrics, and the
registry served at `/metrics`. Keeping it lets Prometheus collect metrics later
without changing app code. It does not start a Prometheus or Grafana server.

The client brings these indirect dependencies into `package-lock.json`:

| Package | Why it is installed |
| --- | --- |
| `@opentelemetry/api` | The client's CPU metrics module imports it to attach trace/span identifiers to metric samples when exemplars are enabled. This app does not enable exemplars or configure a tracing exporter. |
| `tdigest` | Provides percentile estimation for the client's Summary metrics. Our app uses counters and histograms, but this remains a declared dependency of the client. |
| `bintrees` | Required by `tdigest` to keep its data points grouped and ordered in a balanced tree for percentile calculations. |

Only the client is added directly to `package.json`. The lockfile records its
exact version and the resolved indirect dependencies so `npm ci` can reproduce
the installation. These entries should remain even when their optional features
are unused; they belong to the client's dependency tree.

### Running tests

Install the locked dependencies and run the unit tests with:

````powershell
npm ci
npm test
````

The tests use Node's built-in test runner and cover the random generators, date formatting, and metrics instrumentation. They do not require MySQL.

## Continuous integration

The GitHub Actions workflow in `.github/workflows/ci.yml` runs for pull requests and pushes to `main`. It checks out the source, installs dependencies, runs the unit tests, lints both Dockerfiles, validates the Compose configuration, checks the Dockerfiles, and builds the API and frontend images tagged with the commit SHA.

The workflow does not publish images or deploy anything. Image publishing to Amazon ECR will be added separately.

### Dockerfile and Compose checks

The same checks can be run locally when the Docker daemon is available:

````powershell
hadolint Dockerfile
hadolint frontend\Dockerfile
docker compose config
docker build --check -t random-generator-api:check .
docker build --check -t random-generator-web:check -f frontend\Dockerfile .
````

## API Endpoints

### GET /
Returns information about the application and the available endpoints.

Example response:
````
{ 
    "appName": "Random generator", 
    "status": "Up and running!", 
    "availableEndpoints": [ 
        { 
            "url": "/number", 
            "description": "generate a random number" 
        }, 
        { 
            "url": "/letter", 
            "description": "generate a random letter" 
        }, 
        { 
            "url": "/rock-paper-scissors", 
            "description": "generate a random rock - papers - scissors option" 
        } ] 
}
````

### GET /number
Generates a random integer between 0 and 99.

Example response:
````
{ 
    "description": "Generates a random number", 
    "value": 42, 
    "timestamp": "2026-09-06 12:14:42" 
}
````


### GET /letter
Generates a random uppercase letter between A and Z.

Example response:
````
{ 
    "description": "Generates a random letter", 
    "value": "G", 
    "timestamp": "2026-09-06 12:14:42" 
}
````


### GET /rock-paper-scissors
Generates a random option for a rock - paper - scissors game.

Example response:
````
{ 
    "description": "Generates a rock - papers - scissors option", 
    "value": "paper", 
    "timestamp": "2026-09-06 12:14:42" 
}
````

### GET /history

Returns the most recent generated values stored in MySQL. Use `?limit=10` to request a bounded number of rows (between 1 and 100).

### Health endpoints

- `GET /health/live` reports whether the Node.js process is running.
- `GET /health/ready` reports whether the API can connect to MySQL.

## MySQL configuration

The API stores every generated value in a `generations` table. Configure the connection with these environment variables:

```text
DB_HOST (default: 127.0.0.1)
DB_PORT (default: 3306)
DB_NAME (default: random_generator)
DB_USER (default: random_app)
DB_PASSWORD (default: random_password)
```

The Kubernetes manifests provide the non-sensitive values through `mysql-config` and passwords through `mysql-secret`. Docker Compose supplies the same values directly to the API and initializes the local MySQL service with the matching credentials.

## Technologies
- Node.js
- Express.js
- JavaScript ES Modules
