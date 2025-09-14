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
        stage('Deployment') {
	            steps {
	                timeout(time: 15, unit: "MINUTES") {
	                    input message: 'Do you want to approve the deployment?', ok: 'Yes'
	                }
	                echo "Initiating deployment"
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
