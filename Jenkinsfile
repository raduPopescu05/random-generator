pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        timestamps()
    }

    environment {
        IMAGE_TAG = "${BUILD_NUMBER}"
    }

    stages {
        stage('Verify branch') {
            steps {
                script {
                    if (env.BRANCH_NAME != 'jenkins-migration') {
                        error("This pipeline is restricted to the jenkins-migration branch. Current branch: ${env.BRANCH_NAME ?: 'unknown'}")
                    }
                }
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install dependencies') {
            steps {
                sh 'npm ci'
            }
        }

        stage('Run tests') {
            steps {
                sh 'npm test'
            }
        }

        stage('Check Dockerfiles') {
            steps {
                sh '''
                    set -eu
                    docker build --check -t random-generator-api:check .
                    docker build --check -t random-generator-web:check -f frontend/Dockerfile .
                '''
            }
        }

        stage('Build Docker images') {
            steps {
                script {
                    ['AWS_REGION', 'ECR_REGISTRY', 'BACKEND_IMAGE', 'FRONTEND_IMAGE'].each { variableName ->
                        if (!env.getProperty(variableName)?.trim()) {
                            error("Required Jenkins environment variable is missing: ${variableName}")
                        }
                    }
                }
                sh '''
                    set -eu
                    docker build \
                        --tag "$BACKEND_IMAGE:$IMAGE_TAG" \
                        --tag "$BACKEND_IMAGE:latest" \
                        .
                    docker build \
                        --file frontend/Dockerfile \
                        --tag "$FRONTEND_IMAGE:$IMAGE_TAG" \
                        --tag "$FRONTEND_IMAGE:latest" \
                        .
                '''
            }
        }

        stage('Approve ECR push') {
            steps {
                input message: "Approve pushing backend and frontend images for build ${env.BUILD_NUMBER} to ECR?", ok: 'Approve and push'
            }
        }

        stage('Authenticate with ECR') {
            steps {
                sh '''
                    set -eu
                    test -n "$AWS_ACCESS_KEY_ID"
                    test -n "$AWS_SECRET_ACCESS_KEY"
                    aws ecr get-login-password --region "$AWS_REGION" | \
                        docker login --username AWS --password-stdin "$ECR_REGISTRY"
                '''
            }
        }

        stage('Push images to ECR') {
            steps {
                sh '''
                    set -eu
                    docker push "$BACKEND_IMAGE:$IMAGE_TAG"
                    docker push "$BACKEND_IMAGE:latest"
                    docker push "$FRONTEND_IMAGE:$IMAGE_TAG"
                    docker push "$FRONTEND_IMAGE:latest"
                '''
            }
        }
    }
}
