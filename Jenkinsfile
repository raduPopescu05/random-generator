pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        IMAGE_TAG = "${BUILD_NUMBER}"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install dependencies') {
            steps {
                sh 'npm ci'
                sleep time: 5, unit: 'SECONDS'
            }
        }

        stage('Run tests') {
            steps {
                sh '''
                    rm -rf test-results
                    mkdir -p test-results
                    npm test -- \
                        --test-reporter=junit \
                        --test-reporter-destination=test-results/junit.xml
                '''
                sleep time: 5, unit: 'SECONDS'
            }
            post {
                always {
                    junit testResults: 'test-results/junit.xml', allowEmptyResults: false
                }
            }
        }

        stage('Validate Jenkins configuration') {
            steps {
                script {
                    ['AWS_REGION', 'ECR_REGISTRY', 'BACKEND_IMAGE', 'FRONTEND_IMAGE'].each { variableName ->
                        if (!env.getProperty(variableName)?.trim()) {
                            error("Required Jenkins environment variable is missing: ${variableName}")
                        }
                    }
                    sleep time: 5, unit: 'SECONDS'
                }
            }
        }

        stage('Build and validate Docker images') {
            steps {
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
                sleep time: 5, unit: 'SECONDS'
            }
        }

        stage('Approve ECR push') {
            steps {
                input message: "Approve pushing backend and frontend images for build ${env.BUILD_NUMBER} to ECR?", ok: 'Approve and push'
            }
        }

        stage('Authenticate with ECR') {
            steps {
                sh '''#!/usr/bin/env bash
                    set -euo pipefail
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
                sleep time: 5, unit: 'SECONDS'
            }
        }
    }
}
