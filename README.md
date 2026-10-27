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

First copy `.env.example` to `.env` and set a unique `GRAFANA_ADMIN_PASSWORD`
(do not overwrite an existing `.env`). Then start the stack:
````
docker compose up -d --build
````

This builds the API and Nginx frontend locally and starts five services: MySQL,
the API, the frontend, Prometheus, and Grafana. No ECR login is needed.
MySQL is available internally as `db:3306`; `mysql-data` preserves its data.
Open `http://localhost:3000` for the app, `http://localhost:9090` for Prometheus,
and `http://localhost:3001` for Grafana. Sign in to Grafana as `admin` using the
password from `.env`. Three dashboards are provisioned in the **Random Generator**
folder: API Overview, Node.js Runtime, and Generation & Database Activity.

See [the monitoring README](monitoring/README.md) for sample traffic, dashboard
usage, configuration, troubleshooting, and monitoring-only reset instructions.

The API waits for the MySQL health check before starting, and the web service waits
for the API health check. Prometheus scrapes the internal API metrics endpoint every
15 seconds. Published ports listen on all host network interfaces.

Stop the stack with:
````
docker compose down
````

The following removes **all** stack volumes, including generation history,
Prometheus history, and Grafana settings:

````powershell
docker compose down -v
````

### Running tests

Install the locked dependencies and run the unit tests with:

````powershell
npm ci
npm test
````

The tests use Node's built-in test runner and cover the random generators and date formatting. They do not require MySQL.

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
