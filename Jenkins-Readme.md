# Jenkins pipeline for the `jenkins-migration` branch

This repository contains a Jenkins pipeline in [`Jenkinsfile`](Jenkinsfile). It mirrors the CI/CD flow used by the GitHub Actions workflow:

1. Check out the repository.
2. Install Node.js dependencies.
3. Run the Node.js tests.
4. Build and validate both Docker images. A successful Docker build validates the corresponding Dockerfile.
5. Tag both Docker images.
6. Wait for a manual approval.
7. Authenticate with Amazon ECR.
8. Push both images with the Jenkins build number and `latest` tags.

The pipeline is intentionally restricted to the `jenkins-migration` branch. The branch is created locally by this migration work; Jenkins cannot discover it from GitHub until you push it to the `origin` remote.

## Prerequisites

Install the following on the computer running Jenkins:

- Docker Desktop with Linux containers enabled.
- A GitHub account that can read the repository.
- AWS credentials with permission to authenticate to ECR and upload image layers/manifests.
- Access to the `jenkins-migration` branch after it has been pushed to GitHub.

The AWS identity needs ECR permissions for both repositories:

- `dev/random-generator-repository/backend`
- `dev/random-generator-repository/frontend`

At minimum, the identity needs permission to obtain an ECR authorization token and to upload image layers and manifests.

## Start Jenkins locally with Docker

The example below builds the repository's custom Jenkins image, uses a named volume for persistent Jenkins data, mounts the Docker socket for Docker builds, and uses a local environment file for AWS/ECR configuration.

Create a local file named `jenkins.env` in the repository root. Use real values locally and never commit this file:

```text
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=eu-central-1
ECR_REGISTRY=834251003876.dkr.ecr.eu-central-1.amazonaws.com
BACKEND_IMAGE=834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/backend
FRONTEND_IMAGE=834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/frontend
```

Create the Jenkins data volume:

```powershell
docker volume create jenkins_home
```

Build the custom Jenkins image from the repository root:

```powershell
docker build -t random-generator-jenkins:latest -f jenkins/Dockerfile .
```

The image is based on `jenkins/jenkins:lts-jdk21` and includes Node.js 22, npm, Docker CLI, AWS CLI, Git, Pipeline, GitHub Branch Source, JUnit, and Pipeline: Stage View plugins.

Start Jenkins from PowerShell:

```powershell
docker run -d --name jenkins --restart unless-stopped --user root --env-file .\jenkins.env -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home -v /var/run/docker.sock:/var/run/docker.sock random-generator-jenkins:latest
```

Open Jenkins at [http://localhost:8080](http://localhost:8080).

The Docker socket gives the Jenkins container control over the Docker daemon on the host. Running the local container as root also simplifies access to that socket. Use this setup only on a trusted development machine; do not expose it as an unprotected production Jenkins instance.

Verify that the custom image contains the required tools:

```powershell
docker exec jenkins node --version
docker exec jenkins npm --version
docker exec jenkins docker --version
docker exec jenkins aws --version
```

The named `jenkins_home` volume preserves Jenkins configuration and job data. Rebuild the custom image and recreate the container when changing installed tools or plugins; the named volume preserves the Jenkins data.

## Complete the Jenkins setup wizard

1. Retrieve the initial administrator password:

   ```powershell
   docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
   ```

2. Enter the password at [http://localhost:8080](http://localhost:8080).
3. Choose **Install suggested plugins**.
4. Confirm that these plugins are installed under **Manage Jenkins → Plugins**:
   - Pipeline
   - Git
   - GitHub Branch Source
   - JUnit
   - Pipeline: Stage View

The custom image installs these plugins during the Docker build. The Jenkinsfile uses shell commands for Docker and AWS, so the Docker Pipeline plugin is not required.

## Push the branch to GitHub

The branch is intentionally local until you decide to publish it. From the repository directory, push it when ready:

```powershell
git push --set-upstream origin jenkins-migration
```

Jenkins must be able to read this remote branch before the Pipeline job can load the Jenkinsfile.

## Create the Pipeline job

1. In Jenkins, select **New Item**.
2. Enter a name such as `random-generator-jenkins`.
3. Select **Pipeline** and choose **OK**.
4. Scroll to the **Pipeline** section.
5. Set **Definition** to **Pipeline script from SCM**.
6. Set **SCM** to **Git**.
7. Configure the repository URL:

   ```text
   https://github.com/raduPopescu05/random-generator.git
   ```

8. Add GitHub credentials if the repository requires authentication. A GitHub fine-grained token should have repository contents read access.
9. Set **Branch Specifier** to:

   ```text
   */jenkins-migration
   ```

10. Set **Script Path** to:

   ```text
   Jenkinsfile
   ```

11. Save the job.

The branch specifier ensures that this job checks out only `jenkins-migration`. The Jenkinsfile also contains only the build, approval, and ECR stages; it does not need a Multibranch-only `BRANCH_NAME` variable.

## Triggering builds

### Manual scan

For a local Jenkins instance, select **Build Now** after pushing a new commit.

### GitHub webhook

GitHub cannot normally reach `localhost:8080` directly. To use automatic webhooks, expose Jenkins through a secure tunnel such as Cloudflare Tunnel or ngrok, then configure the repository webhook URL as:

```text
https://your-public-jenkins-host/github-webhook/
```

Enable **GitHub hook trigger for GITScm polling** in the Pipeline job when available. Do not expose Jenkins without authentication and appropriate network controls.

## Run and approve the pipeline

1. Open the `random-generator-jenkins` job.
2. Select **Build Now**, or wait for the configured trigger.
3. Jenkins runs dependency installation, tests, publishes the JUnit report, validates configuration, and builds both Docker images.
4. The pipeline pauses at **Approve ECR push**.
5. Open the paused build and select **Proceed** to approve the push.
6. Jenkins then authenticates with ECR and pushes:

   - `${BUILD_NUMBER}` and `latest` for the backend image.
   - `${BUILD_NUMBER}` and `latest` for the frontend image.

The Jenkins build number is used as the immutable build tag for that Jenkins job.

## Troubleshooting

### Jenkins cannot run `docker`

Confirm that Docker CLI is installed inside the custom Jenkins container:

```powershell
docker exec jenkins docker --version
```

Confirm that the Docker socket is mounted:

```powershell
docker exec jenkins ls -l /var/run/docker.sock
```

If the socket is missing, recreate the container with:

```text
-v /var/run/docker.sock:/var/run/docker.sock
```

### Jenkins cannot run `aws`

Verify that AWS CLI is included in the custom image:

```powershell
docker exec jenkins aws --version
```

If it is missing, rebuild `random-generator-jenkins:latest` from `jenkins/Dockerfile` and recreate the container.

### AWS credentials are missing

Confirm that `jenkins.env` contains `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, and recreate the container if the file was changed after startup. Never print these variables in pipeline logs.

### ECR login or push fails

Check the AWS region, registry URI, repository names, and IAM permissions. The registry login must use the registry host only, while image names include the repository paths.

### The branch is not discovered

Confirm that `jenkins-migration` was pushed to GitHub, the repository URL is correct, the Branch Specifier is `*/jenkins-migration`, and the job was saved before selecting **Build Now**.

### The pipeline stops at the branch guard

The Jenkins job is intended only for `jenkins-migration`. Confirm that the Pipeline job uses the Branch Specifier `*/jenkins-migration`.

### The approval prompt is not visible

Open the running build’s Console Output or Pipeline Steps. The build should be paused at **Approve ECR push**. The ECR login and push stages do not run until **Proceed** is selected.

### Test results are not visible

The pipeline uses Node.js 22's built-in JUnit reporter and writes `test-results/junit.xml`. The JUnit plugin publishes that file after the test stage, including when a test fails. Rebuild the Jenkins image if the JUnit plugin is not installed.
