pipeline {
    agent {
        label 'test-label'
    }

    stages {
        stage('init&plan') {
            steps {
                sh '''
                terraform init
                terraform plan -out=plan.out -no-color
                '''
            }
        }
        stage('Manual Approval') {
            steps {
                script {
                    def userInput = input(id: 'ProceedConfirmation', message: 'Do you want to proceed with deployment?', ok: 'Proceed', submitter: 'admin, devops')
                    echo "User selected: ${userInput.Environment}"
                }
            }
        }
        stage('apply') {
            steps {
                sh '''
                terraform apply plan.out -no-color
                '''
            }
        }
    }
}
