pipeline {
    agent any

    // Inject your AWS Credentials so Jenkins can access the S3 backend and delete the AWS resources
    environment {
        AWS_ACCESS_KEY_ID     = AKIA3RYC5VVR6TLBLPGM('AWS_ACCESS_KEY')
        AWS_SECRET_ACCESS_KEY = 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('AWS_SECRET_KEY')
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
                // The -auto-approve flag ensures Jenkins doesn't pause for human confirmation
                sh 'terraform destroy -auto-approve'
            }
        }
    }
}
