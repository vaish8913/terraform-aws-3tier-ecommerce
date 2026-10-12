pipeline {
    agent any

    environment {
        // This references the IDs we created in Jenkins Credentials
        AWS_ACCESS_KEY_ID     = credentials('AWS_ACCESS_KEY')
        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_KEY')
    }

    stages {
        stage('Initialize Backend') {
            steps {
                echo 'Connecting to AWS S3 Remote State...'
                sh 'terraform init'
            }
        }

        stage('Destroy Infrastructure') {
            steps {
                echo '⚠️ WARNING: Tearing down all 3-tier e-commerce resources...'
                sh 'terraform destroy -auto-approve'
            }
        }
    }
}
