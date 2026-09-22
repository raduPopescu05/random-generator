pipeline {
    agent any

    stages {
        stage('Build code') {
            steps {
                sh 'npm ci'
            }
        }
        stage('Test code ') {
            steps {
                sh 'npm test'    
            }
        }

        stage('Build dockefile for backend') {
            steps {
                echo 'checking dockerfile for backend'
                sh '''
                docker build --check .
                docker build --tag backend:latest .
                docker image ls | grep backend
                '''

            }
        }
    }
}