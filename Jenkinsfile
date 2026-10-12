// Yantra frontend CI/CD: check -> build Docker image -> smoke test -> push -> deploy to Kubernetes.
//
// Runs on a Windows Jenkins agent (steps use PowerShell). The agent needs docker and kubectl on PATH.
// Jenkins credentials to create (Manage Jenkins -> Credentials):
//   - "docker-registry" : Username with password for your registry (e.g. Docker Hub user + access token)
//   - "kubeconfig"      : Secret file containing the kubeconfig for the target cluster
pipeline {
  agent any

  parameters {
    string(name: 'REGISTRY', defaultValue: '', description: 'Registry host + namespace, e.g. docker.io/yourname or ghcr.io/yourname. Leave empty to build locally without pushing.')
    booleanParam(name: 'DEPLOY', defaultValue: true, description: 'Deploy to Kubernetes after a successful build')
  }

  environment {
    APP = 'yantra-frontend'
    PORT = '8080'
    TAG = "${env.BUILD_NUMBER}"
    IMAGE = "${params.REGISTRY ? params.REGISTRY + '/' : ''}yantra-frontend"
  }

  options {
    timestamps()
    timeout(time: 20, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build image') {
      steps {
        // The Dockerfile syntax-checks the JavaScript in its first stage, so a bad file fails the build.
        powershell '''
          $ErrorActionPreference = 'Continue'
          docker build -t "${env:IMAGE}:${env:TAG}" -t "${env:IMAGE}:latest" .
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        '''
      }
    }

    stage('Smoke test') {
      steps {
        powershell '''
          $ErrorActionPreference = 'Continue'
          $name = "${env:APP}-ci-${env:TAG}"
          docker run -d --name $name "${env:IMAGE}:${env:TAG}"
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
          for ($i = 0; $i -lt 15; $i++) {
            $health = docker exec $name wget -qO- "http://127.0.0.1:${env:PORT}/healthz" 2>$null
            $page = (docker exec $name wget -qO- "http://127.0.0.1:${env:PORT}/" 2>$null) -join "`n"
            if ($health -eq 'ok' -and $page -match '<title>Yantra') {
              Write-Output 'Smoke test passed'
              exit 0
            }
            Start-Sleep -Seconds 2
          }
          Write-Output 'Smoke test failed'
          docker logs $name
          exit 1
        '''
      }
      post {
        always {
          powershell '''
            $ErrorActionPreference = 'Continue'
            docker rm -f "${env:APP}-ci-${env:TAG}" 2>$null
            exit 0
          '''
        }
      }
    }

    stage('Push image') {
      when { expression { params.REGISTRY?.trim() } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'docker-registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
          powershell '''
            $ErrorActionPreference = 'Continue'
            $registryHost = $env:REGISTRY.Split('/')[0]
            $env:REG_PASS | docker login $registryHost -u $env:REG_USER --password-stdin
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            docker push "${env:IMAGE}:${env:TAG}"
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            docker push "${env:IMAGE}:latest"
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
          '''
        }
      }
      post {
        always {
          powershell '''
            $ErrorActionPreference = 'Continue'
            docker logout $env:REGISTRY.Split('/')[0]
            exit 0
          '''
        }
      }
    }

    stage('Deploy to Kubernetes') {
      when { expression { params.DEPLOY } }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          powershell '''
            $ErrorActionPreference = 'Continue'
            kubectl apply -f k8s/namespace.yaml
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            kubectl apply -f k8s/service.yaml
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            # Deploy the exact image this build produced.
            (Get-Content k8s/deployment.yaml) -replace "image: ${env:APP}:latest", "image: ${env:IMAGE}:${env:TAG}" | kubectl apply -f -
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            kubectl -n yantra rollout status "deployment/${env:APP}" --timeout=120s
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
          '''
        }
      }
    }
  }

  post {
    success {
      echo "Built ${env.IMAGE}:${env.TAG}"
    }
    failure {
      echo 'Pipeline failed. Check the stage logs above.'
    }
  }
}
