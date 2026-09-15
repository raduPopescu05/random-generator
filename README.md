# RANDOM GENERATOR 
A simple Node.js and Express application that exposes API endpoints for generating random numbers and letters.

## Features
- Returns basic application information
- Generates a random number between 0 and 99
- Generates a random uppercase letter from A to Z
- Returns responses in JSON format

## Requirements
- Node.js
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

Start the service with:
````
docker compose up --build
````

This starts three services: a MySQL database, an API container, and an Nginx web container. MySQL is available to the other Compose services as `db:3306`; the named `mysql-data` volume preserves its data. Open `http://localhost:3000` for the UI.

The API waits for the MySQL health check before starting, and the web service waits for the API health check. Stop the stack with `Ctrl+C`, or run `docker compose down` in another terminal.

Stop the stack with:
````
docker compose down
````

To remove the database volume and start with an empty history, run:

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

To run the end-to-end test, start the complete Compose stack first:

````powershell
docker compose up --build -d
npm run test:e2e
docker compose down -v
````

The end-to-end test checks the health endpoints, all generators, and persistence through `/history`.

## Continuous integration

The GitHub Actions workflow in `.github/workflows/ci.yml` runs for pull requests and pushes to `develop`. It uses three dependent jobs: `build-and-test` installs dependencies, runs unit tests, lints and checks Dockerfiles, builds both images, and uploads them as an artifact; `compose-start` validates and starts the Compose stack; `e2e-tests` starts its own stack and tests the running application.

The workflow does not publish images or deploy anything. Image publishing to Amazon ECR will be added separately. Jobs run on separate GitHub-hosted runners, so the Docker image archive is transferred between jobs and each Compose job starts its own stack.

## Jenkins Multibranch Pipeline

The root-level `Jenkinsfile` contains the equivalent CI pipeline for Jenkins. A Jenkins Multibranch Pipeline scans the GitHub repository, discovers branches that contain this file, and runs the pipeline for each branch or pull request.

The stages are:

```text
Checkout
→ npm ci
→ npm test
→ Hadolint Dockerfile checks
→ docker compose config validation
→ Dockerfile checks
→ Build API image
→ Build frontend image
```

The Jenkinsfile does not publish images, access Amazon ECR, or deploy to Kubernetes. Images are tagged with the checked-out commit and remain on the Jenkins agent.

### Configure the Multibranch job

Create a Multibranch Pipeline job using this repository:

```text
https://github.com/raduPopescu05/random-generator.git
```

Configure branch discovery according to the branches you want Jenkins to build. The Jenkinsfile itself does not hardcode `main` or `develop`.

The Jenkins agent must provide:

- Git
- Node.js 24 and npm
- Docker CLI and access to a Docker daemon
- Docker Compose v2
- Hadolint

When Jenkins is later run in Docker, the agent will need Docker CLI access to the host Docker daemon, commonly through `/var/run/docker.sock`. Jenkins’ Declarative Pipeline linter can validate the Jenkinsfile after Jenkins is running.

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
