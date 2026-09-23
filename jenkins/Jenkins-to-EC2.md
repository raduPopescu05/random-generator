# Jenkins on Amazon EC2: Production Architecture Guide

This guide explains how to operate the Jenkins pipeline for this repository in a production AWS environment using Amazon EC2.

It is a theory and architecture guide. It does not replace the local Jenkins setup instructions in [`Jenkins-Readme.md`](Jenkins-Readme.md), and it does not require changes to the current [`Jenkinsfile`](Jenkinsfile).

## Recommended production architecture

```text
Developer push
      |
      v
GitHub webhook over HTTPS
      |
      v
Application Load Balancer
      |
      v
Jenkins controller on EC2
      |
      v
Temporary Jenkins build agent
      |
      +--> npm install and tests
      +--> JUnit test report
      +--> Backend Docker image
      +--> Frontend Docker image
      +--> Manual approval
      +--> ECR authentication and push
```

The Jenkins controller coordinates jobs and stores Jenkins configuration. Build agents perform the expensive and potentially untrusted work. Amazon ECR stores the resulting images; it does not run them.

The application still needs a separate runtime and deployment step after image publication, such as Amazon ECS, Amazon EKS, or Docker on EC2.

## Jenkins controller on EC2

The controller is the Jenkins server that provides the web UI, schedules jobs, manages credentials, and coordinates agents.

Recommended production characteristics:

- Use a dedicated EC2 instance for Jenkins.
- Place the instance in a private subnet when possible.
- Put an Application Load Balancer in front of Jenkins.
- Use an HTTPS listener with an ACM certificate.
- Use a Route 53 DNS name such as `jenkins.example.com`.
- Use AWS Systems Manager Session Manager instead of exposing SSH to the internet.
- Store Jenkins data on a persistent EBS volume.
- Keep the controller available, but avoid using it as the build worker.

The security group should allow only the traffic that is required:

- HTTPS from the organization’s trusted networks, VPN, or identity-aware access layer.
- Agent communication from approved agent networks if inbound agent connections are used.
- Outbound access to GitHub, AWS APIs, package registries, and ECR.
- No unrestricted public SSH access.

Jenkins stores its configuration, jobs, plugin state, build history, and credential metadata under `JENKINS_HOME`. Treat this directory as persistent application data.

## Build agents

Builds should run on agents rather than on the Jenkins controller. Agents can be static EC2 instances or temporary workers created for a build and removed afterward.

### Static agents

Static agents are always-running EC2 instances registered with Jenkins. They are simple to understand but continue to incur cost even when idle and require patching and cleanup.

### Temporary agents

Temporary agents are created when Jenkins needs capacity and terminated when the work is finished. They reduce idle cost and provide cleaner build environments.

Possible implementations include:

- Jenkins Amazon EC2 plugin with an agent AMI.
- ECS or Fargate-based Jenkins agents.
- A separate autoscaling EC2 agent pool.
- Kubernetes-based Jenkins agents if the organization already operates Kubernetes.

The Jenkins Amazon EC2 plugin can create agents when the build cluster needs capacity and remove unused agents afterward. See the [Jenkins Amazon EC2 plugin](https://plugins.jenkins.io/ec2/).

### Required agent tools

An agent running this repository’s pipeline needs:

- Node.js 22.
- npm.
- Git.
- Docker CLI.
- Docker BuildKit or a compatible modern Docker build implementation.
- AWS CLI.
- Network access to GitHub, npm, and Amazon ECR.

The agent must also have access to a Docker daemon. Prefer a dedicated build agent or isolated build service rather than mounting the Docker socket of the Jenkins controller into arbitrary jobs.

## AWS networking

A typical layout is:

```text
Public subnet:
  Application Load Balancer

Private subnet:
  Jenkins controller EC2
  Optional Jenkins EC2 agents

AWS services:
  ECR, CloudWatch, Systems Manager, Secrets Manager, AWS Backup
```

Private agents may need a NAT Gateway or VPC endpoints to reach required services. At minimum, consider endpoints or controlled outbound access for:

- Amazon ECR API.
- Amazon ECR Docker registry.
- Amazon S3, if required by AWS tooling or backups.
- Systems Manager.
- CloudWatch Logs.

The exact endpoint design depends on whether agents need general internet access for GitHub and npm. Restrict outbound traffic where practical, but ensure the pipeline can actually reach its source and package dependencies.

## IAM design

Use IAM roles instead of long-lived AWS access keys wherever possible. AWS documents IAM roles as the preferred way for applications running on EC2 to receive temporary AWS credentials. See [Amazon ECR identity and access management](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security-iam.html) and [IAM roles for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html).

Use separate roles for separate responsibilities:

### Jenkins controller role

The controller role should contain only permissions needed by the controller, such as:

- Discovering or managing build agents, if Jenkins creates them.
- Reading required AWS configuration.
- Writing logs or metrics if configured.
- Reading backup or recovery resources if required.

Do not give the controller broad administrator permissions simply because it orchestrates jobs.

### Build agent role

The agent that builds and publishes images should have only the ECR permissions required by this pipeline:

```text
ecr:GetAuthorizationToken
ecr:BatchCheckLayerAvailability
ecr:InitiateLayerUpload
ecr:UploadLayerPart
ecr:CompleteLayerUpload
ecr:PutImage
```

Limit repository access to:

```text
dev/random-generator-repository/backend
dev/random-generator-repository/frontend
```

If Jenkins and ECR are in different AWS accounts, use a tightly scoped role-assumption policy and require the Jenkins role to assume the target account’s publishing role.

### Human access

Human users should use federated access or SSO to access AWS. Do not share the build agent role or use the AWS root account for pipeline operations.

## ECR repositories and image tags

This project publishes two images:

```text
834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/backend
834251003876.dkr.ecr.eu-central-1.amazonaws.com/dev/random-generator-repository/frontend
```

The backend is built from the root `Dockerfile`. The frontend is built from `frontend/Dockerfile` using the repository root as the build context.

### Recommended tags

Use immutable tags for deployment:

```text
backend:git-<commit-sha>
backend:build-<jenkins-build-number>
frontend:git-<commit-sha>
frontend:build-<jenkins-build-number>
```

The current Jenkins pipeline uses the Jenkins build number and `latest`. `latest` can be useful for development, but production deployments should reference an immutable commit or build tag so that a deployment can always be reproduced.

A common policy is:

- Development: publish `latest` and a build tag.
- Staging: deploy a specific build or commit tag.
- Production: deploy only an approved immutable image digest or commit tag.

Configure ECR lifecycle policies to remove unneeded old images while retaining the tags and digests required for rollback and auditing. Enable image scanning according to the organization’s vulnerability-management policy.

## GitHub integration

GitHub should notify Jenkins when the branch changes. The production flow is:

1. A developer pushes to GitHub.
2. GitHub sends a signed webhook over HTTPS.
3. The load balancer routes the request to Jenkins.
4. Jenkins checks out the configured branch.
5. Jenkins loads the `Jenkinsfile` from the repository.

Use a GitHub App where possible. A narrowly scoped read-only token is acceptable for simple repository access, but it should have only the permissions required to read the repository and manage the webhook if that is part of the integration.

The current migration job is intended to build only:

```text
jenkins-migration
```

For a regular Jenkins Pipeline job, configure the SCM branch specifier as:

```text
*/jenkins-migration
```

For a Multibranch Pipeline, configure the branch source to include only that branch. Branch filtering in the Jenkins job is the primary restriction; the repository branch and permissions should also prevent unintended production jobs.

A Jenkins instance running only on `localhost` cannot receive GitHub webhooks. Use a public HTTPS endpoint through an ALB, VPN-accessible webhook relay, or a secure tunnel for development testing.

## Pipeline flow for this repository

The Jenkinsfile should represent these stages:

1. **Checkout**: retrieve the repository and Jenkinsfile.
2. **Install dependencies**: run `npm ci` with Node.js 22.
3. **Run tests**: run the Node.js test suite.
4. **Publish test results**: generate JUnit XML and publish it with Jenkins’ JUnit publisher.
5. **Validate configuration**: confirm that the ECR variables and region are present.
6. **Build and validate Docker images**: build the backend and frontend images. A successful Docker build validates its Dockerfile; avoid relying on unsupported `docker build --check` flags on older agent toolchains.
7. **Approve ECR push**: require an authorized human approval before publishing.
8. **Authenticate with ECR**: obtain an ECR login token using the agent IAM role.
9. **Push images to ECR**: push the backend and frontend build tags and, where allowed, `latest`.

The ECR push is separate from the build approval so that a failed test or image build never reaches the registry. In a more advanced setup, the build stage can publish an immutable candidate image first, and the approval stage can promote the same digest to a release repository or deployment environment.

## Secrets and credentials

Do not commit `jenkins.env`, AWS access keys, GitHub tokens, or private keys to the repository.

For production, prefer this order:

1. EC2 instance profile or agent IAM role for AWS access.
2. Jenkins Credentials Store for GitHub integration and non-AWS secrets.
3. AWS Secrets Manager or SSM Parameter Store for application secrets.
4. Environment variables only as a controlled injection mechanism, never as committed configuration.

If Jenkins uses its Credentials Store, bind credentials only in the stage that needs them. Avoid placing secrets in global controller environment variables where every job can potentially access them.

The current local setup uses environment variables because it is intended for a development Docker container. Replace that approach with IAM roles and Jenkins-managed credentials for production.

## Manual approval and governance

The current pipeline pauses before ECR authentication and image publication. In production, restrict the approval permission to an authorized release group.

Recommended controls include:

- Require approval before staging or production publication.
- Record who approved each image promotion.
- Separate build, publish, and deploy permissions.
- Require successful tests and security scans before approval.
- Prevent a user from approving their own high-risk production change when separation of duties is required.
- Use change tickets or deployment records for regulated environments.

Jenkins’ `input` step is suitable for a basic approval. Larger organizations may use a deployment approval system or an external change-management integration.

## Backups and disaster recovery

Back up the Jenkins controller’s persistent state, especially:

- `JENKINS_HOME`.
- Job definitions and pipeline configuration.
- Installed plugin list and versions.
- Credentials metadata and secret-encryption keys.
- Build history and archived test reports if required for audit.

Use EBS snapshots, AWS Backup, and/or copies to a separate S3-backed backup location. Store backups in a separate failure domain or account where practical.

Define:

- **Recovery Point Objective (RPO)**: the maximum acceptable amount of Jenkins history or configuration that can be lost.
- **Recovery Time Objective (RTO)**: the maximum acceptable time to restore a working controller.

Jenkins controllers are stateful and should not be treated as an active-active service by simply launching two controllers against the same data directory. A common recovery model is one active controller, automated backups, and an infrastructure-as-code process that can recreate the instance and restore `JENKINS_HOME`.

Test restoration periodically instead of assuming that a successful backup automatically means a successful recovery.

## Monitoring and operations

Monitor at least:

- EC2 instance health.
- CPU, memory, and disk usage.
- EBS volume performance and free space.
- Jenkins queue length.
- Agent provisioning failures.
- Build failure rate and duration.
- Plugin errors and controller logs.
- GitHub webhook delivery failures.
- ECR authentication and push failures.
- Backup success and restore-test results.

Send Jenkins and infrastructure logs to CloudWatch or the organization’s centralized logging system. Alert on a full Jenkins disk, a growing build queue, repeated agent failures, and repeated ECR failures.

## Security controls

At minimum:

- Use HTTPS for Jenkins.
- Require authentication and disable anonymous access.
- Apply least-privilege Jenkins permissions.
- Keep the controller off the public internet when possible.
- Restrict security groups and outbound access.
- Use IAM roles instead of long-lived AWS keys.
- Keep Jenkins and plugins patched.
- Review plugins before installing them.
- Do not run untrusted pull-request code on the controller.
- Use isolated or disposable agents for untrusted builds.
- Do not expose the Docker socket to jobs that do not need it.
- Mask secrets in logs and never echo them.
- Protect GitHub webhooks with HTTPS and a secret.
- Maintain an audit trail for approvals and image promotion.

The Docker socket grants powerful control over the host Docker daemon. If socket access is required for image builds, isolate the agent and ensure that only trusted pipeline code can run on it.

## Practical production mapping for this repository

```text
GitHub repository
  └── jenkins-migration branch
       └── Jenkinsfile

Jenkins controller EC2
  ├── Persistent EBS volume for JENKINS_HOME
  ├── IAM role for Jenkins infrastructure tasks
  ├── HTTPS through an Application Load Balancer
  └── GitHub webhook endpoint

Temporary Jenkins build agent
  ├── Node.js 22 and npm
  ├── Docker BuildKit
  ├── AWS CLI
  ├── IAM role limited to ECR publishing
  └── JUnit result publishing

Amazon ECR
  ├── dev/random-generator-repository/backend
  └── dev/random-generator-repository/frontend
```

The pipeline builds the backend and frontend separately but publishes them as one approved release unit. The release metadata should identify the source commit, Jenkins build number, image tags, and image digests.

## Production-readiness checklist

- [ ] Jenkins is on a dedicated EC2 instance.
- [ ] Jenkins data is on persistent EBS storage.
- [ ] Jenkins is protected by HTTPS and authentication.
- [ ] The controller is private or strongly access-restricted.
- [ ] Build workloads run on separate agents.
- [ ] Agents have Node.js 22, Docker/BuildKit, AWS CLI, and Git.
- [ ] Jenkins and agents use IAM roles instead of long-lived AWS keys.
- [ ] ECR permissions are limited to the two required repositories.
- [ ] GitHub access uses a GitHub App or least-privilege token.
- [ ] The webhook endpoint is HTTPS and protected.
- [ ] The job is restricted to the intended branch.
- [ ] Tests publish JUnit results.
- [ ] Backend and frontend images use immutable tags.
- [ ] ECR scanning and lifecycle policies are enabled.
- [ ] ECR publication requires the intended approval.
- [ ] Jenkins backups are automated.
- [ ] Jenkins restoration has been tested.
- [ ] CloudWatch or centralized monitoring is configured.
- [ ] Jenkins plugins are reviewed and regularly updated.
- [ ] A recovery runbook exists for controller and agent failure.

## Jenkins on EC2 versus managed alternatives

Jenkins on EC2 provides broad plugin support and control, but the team is responsible for:

- Controller patching.
- Plugin compatibility.
- Persistent storage.
- Backups and recovery.
- Security hardening.
- Agent capacity.
- Monitoring and incident response.

Managed alternatives can reduce this operational burden:

- AWS CodeBuild for managed build workers.
- AWS CodePipeline for AWS-native orchestration.
- GitHub Actions with AWS OIDC for GitHub-native workflows without long-lived AWS keys.
- ECS or Fargate for isolated containerized build workers.

Jenkins is a good fit when the organization already depends on Jenkins plugins, shared libraries, existing governance, or cross-platform build orchestration. A managed service may be preferable when minimizing infrastructure ownership is the priority.
