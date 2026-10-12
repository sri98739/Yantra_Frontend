// Yantra frontend CI/CD: check -> build Docker image -> smoke test -> push -> run the container with Docker.
//
// Runs on a Windows Jenkins agent (steps use PowerShell). The agent needs docker on PATH.
// Jenkins credentials (Manage Jenkins -> Credentials), only needed when REGISTRY is set:
//   - "docker-registry" : Username with password for your registry (e.g. Docker Hub user + access token)
pipeline {
  agent any

  parameters {
    string(name: 'REGISTRY', defaultValue: '', description: 'Registry host + namespace, e.g. docker.io/yourname or ghcr.io/yourname. Leave empty to build locally without pushing.')
    booleanParam(name: 'DEPLOY', defaultValue: true, description: 'Run the new image as a container on this machine after a successful build')
    string(name: 'HOST_PORT', defaultValue: '3000', description: 'Port on this machine to publish the app on')
  }

  environment {
    APP = 'yantra-frontend'
    PORT = '8080'
    // params.HOST_PORT is empty on the first build after the parameter is added, so fall back to the default.
    HOST_PORT = "${params.HOST_PORT ?: '3000'}"
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

    stage('Deploy with Docker') {
      when { expression { params.DEPLOY } }
      steps {
        powershell '''
          $ErrorActionPreference = 'Continue'
          # Replace the previously deployed container (if any) with the image this build produced.
          docker rm -f $env:APP 2>$null
          docker run -d --name $env:APP --restart unless-stopped -p "${env:HOST_PORT}:${env:PORT}" "${env:IMAGE}:${env:TAG}"
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
          for ($i = 0; $i -lt 15; $i++) {
            try {
              $res = Invoke-WebRequest -UseBasicParsing "http://localhost:${env:HOST_PORT}/healthz" -TimeoutSec 3
              if ($res.Content -eq 'ok') {
                Write-Output "Deployed: http://localhost:${env:HOST_PORT}/"
                exit 0
              }
            } catch { }
            Start-Sleep -Seconds 2
          }
          Write-Output 'Deployed container did not become healthy'
          docker logs $env:APP
          exit 1
        '''
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
