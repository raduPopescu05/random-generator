pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        timestamps()
    }

    environment {
        DOCKER_BUILDKIT = '1'
        COMPOSE_DOCKER_CLI_BUILD = '1'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    def commit = sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim()
                    env.IMAGE_TAG = commit ?: "build-${env.BUILD_NUMBER}"
                }
            }
        }

        stage('Install dependencies') {
            steps {
                sh 'npm ci'
            }
        }

        stage('Unit tests') {
            steps {
                sh 'npm test'
            }
        }

        stage('Lint Dockerfiles') {
            steps {
                sh 'hadolint Dockerfile'
                sh 'hadolint frontend/Dockerfile'
            }
        }

        stage('Validate Compose') {
            steps {
                sh 'docker compose config --quiet'
            }
        }

        stage('Check Dockerfiles') {
            steps {
                sh 'docker build --check -t random-generator-api:check .'
                sh 'docker build --check -t random-generator-web:check -f frontend/Dockerfile .'
            }
        }

        stage('Build API image') {
            steps {
                sh 'docker build -t random-generator-api:${IMAGE_TAG} .'
            }
        }

        stage('Build frontend image') {
            steps {
                sh 'docker build -t random-generator-web:${IMAGE_TAG} -f frontend/Dockerfile .'
            }
        }
    }

    post {
        always {
            echo 'CI pipeline finished. Images were built locally and were not published.'
        }
    }
}
