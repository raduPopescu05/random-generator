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
                sh '''
                mkdir test-results
                npm test -- \
                    --test-reporter=junit \
                    --test-reporter-destination=test-results/junit.xml
                '''    
            }
        }

        stage('Deploy') {
            steps {
                echo 'Deploying....'
            }
        }
    }
}