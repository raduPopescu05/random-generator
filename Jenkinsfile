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

        stage('Deploy') {
            steps {
                echo 'Deploying....'
            }
        }
    }
}