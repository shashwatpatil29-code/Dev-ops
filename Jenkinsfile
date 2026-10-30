// =============================================================================
// Vehicle Fuel Expense Tracker – delivery pipeline
//
//   Checkout → Build + unit tests → Selenium UI tests → Package/archive
//   → Docker image (versioned) → Push to registry → Deploy → Smoke test
//   → Post-deploy Selenium check
//
// Any failing test stops the run before "Docker Image", so a broken build can
// never reach a running container (Task 10). If the new container fails its
// health check, the previous image is started again automatically.
// =============================================================================
pipeline {
    agent any

    parameters {
        choice(name: 'APP_ENV', choices: ['dev', 'qa', 'prod'],
               description: 'Environment to deploy to. Sets the app port and the APP_ENV value shown in the footer.')
        choice(name: 'DEPLOY_TARGET', choices: ['docker', 'tomcat'],
               description: 'docker = versioned container (Task 12). tomcat = drop the WAR into the Tomcat container (Task 8).')
        string(name: 'REGISTRY', defaultValue: 'localhost:5000',
               description: 'Image registry. Use your Docker Hub username (e.g. vedlad10) to push to Docker Hub instead.')
        string(name: 'MAX_PRICE_PER_LITRE', defaultValue: '115',
               description: 'Alert threshold passed to the app as an environment setting.')
        booleanParam(name: 'SKIP_UI_TESTS', defaultValue: false,
               description: 'Emergency only. Skips Selenium; unit tests still run.')
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timeout(time: 30, unit: 'MINUTES')
    }

    triggers {
        pollSCM('H/2 * * * *')       // commit-triggered builds without needing a public webhook
    }

    environment {
        IMAGE_NAME   = 'fuel-tracker'
        CONTAINER    = "fuel-tracker-${params.APP_ENV}"
        HOST_PORT    = "${params.APP_ENV == 'prod' ? '8083' : (params.APP_ENV == 'qa' ? '8082' : '8081')}"
        DOCKER_NET   = 'ci-net'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                sh 'chmod +x mvnw'
                script {
                    env.APP_VERSION = sh(returnStdout: true,
                        script: './mvnw -q -B help:evaluate -Dexpression=project.version -DforceStdout').trim()
                    env.GIT_SHORT   = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                    env.IMAGE_TAG   = "${env.APP_VERSION}-${env.BUILD_NUMBER}"
                    currentBuild.displayName = "#${env.BUILD_NUMBER} v${env.APP_VERSION} (${env.GIT_SHORT}) → ${params.APP_ENV}"
                }
                sh 'git log --oneline -5'
            }
        }

        stage('Build + Unit tests') {
            steps {
                sh './mvnw -B clean package'
            }
            post {
                always { junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml' }
            }
        }

        stage('Selenium UI tests') {
            when { expression { !params.SKIP_UI_TESTS } }
            steps {
                // boots the app in-process on a random port + fresh in-memory DB, runs the 5 journeys
                sh './mvnw -B failsafe:integration-test failsafe:verify -Dbrowser=htmlunit'
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'target/failsafe-reports/*.xml'
                    archiveArtifacts allowEmptyArchive: true, artifacts: 'target/selenium-screenshots/**'
                }
                failure {
                    echo 'UI tests failed – deployment is blocked. Screenshots/HTML of the failing page are archived above.'
                }
            }
        }

        stage('Archive artefact') {
            steps {
                archiveArtifacts artifacts: 'target/fuel-tracker.war', fingerprint: true
            }
        }

        stage('Docker image') {
            when { expression { params.DEPLOY_TARGET == 'docker' } }
            steps {
                sh """
                    docker build -f Dockerfile.ci \
                      --build-arg APP_VERSION=${APP_VERSION} --build-arg GIT_COMMIT=${GIT_SHORT} \
                      -t ${params.REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} \
                      -t ${params.REGISTRY}/${IMAGE_NAME}:latest .
                    docker image ls ${params.REGISTRY}/${IMAGE_NAME}
                """
            }
        }

        stage('Push to registry') {
            when { expression { params.DEPLOY_TARGET == 'docker' } }
            steps {
                script {
                    if (params.REGISTRY.startsWith('localhost') || params.REGISTRY.contains(':')) {
                        sh "docker push ${params.REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                        sh "docker push ${params.REGISTRY}/${IMAGE_NAME}:latest"
                        // registry evidence (inside the Jenkins container the registry is reachable as "registry")
                        sh "curl -s http://registry:5000/v2/${IMAGE_NAME}/tags/list || curl -s http://${params.REGISTRY}/v2/${IMAGE_NAME}/tags/list || true"
                    } else {
                        // Docker Hub: create a "Username with password" credential with id dockerhub-creds
                        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
                            sh 'echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin'
                            sh "docker push ${params.REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                            sh "docker push ${params.REGISTRY}/${IMAGE_NAME}:latest"
                        }
                    }
                }
            }
        }

        stage('Deploy') {
            steps {
                script {
                    if (params.DEPLOY_TARGET == 'docker') {
                        // remember what was running so we can put it back if the new one is unhealthy
                        env.PREVIOUS_IMAGE = sh(returnStdout: true,
                            script: "docker inspect -f '{{.Config.Image}}' ${CONTAINER} 2>/dev/null || true").trim()
                        echo "Previous image: ${env.PREVIOUS_IMAGE ?: 'none'}"
                        sh "docker network inspect ${DOCKER_NET} >/dev/null 2>&1 || docker network create ${DOCKER_NET}"
                        runContainer("${params.REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}")
                        env.APP_URL = "http://localhost:${HOST_PORT}"
                    } else {
                        sh """
                            docker exec tomcat sh -c 'printf "export APP_ENV=tomcat-${params.APP_ENV}\\nexport MAX_PRICE_PER_LITRE=${params.MAX_PRICE_PER_LITRE}\\nexport DB_URL=jdbc:h2:file:/usr/local/tomcat/data/fueltracker\\n" > /usr/local/tomcat/bin/setenv.sh'
                            docker exec tomcat rm -rf /usr/local/tomcat/webapps/fuel-tracker /usr/local/tomcat/webapps/fuel-tracker.war
                            docker cp target/fuel-tracker.war tomcat:/usr/local/tomcat/webapps/fuel-tracker.war
                            docker restart tomcat
                        """
                        env.APP_URL = 'http://localhost:8090/fuel-tracker'
                    }
                }
            }
        }

        stage('Smoke test') {
            steps {
                script {
                    // From inside the Jenkins container the app is reachable by container name on ci-net;
                    // a Jenkins installed directly on the host uses the published port instead.
                    def inDocker = sh(returnStatus: true, script: 'test -f /.dockerenv') == 0
                    if (params.DEPLOY_TARGET == 'docker') {
                        env.CHECK_URL = inDocker ? "http://${CONTAINER}:8080" : "http://localhost:${HOST_PORT}"
                    } else {
                        env.CHECK_URL = inDocker ? 'http://tomcat:8080/fuel-tracker' : 'http://localhost:8090/fuel-tracker'
                    }
                    def healthy = waitForHealth(env.CHECK_URL)
                    if (!healthy) {
                        if (params.DEPLOY_TARGET == 'docker' && env.PREVIOUS_IMAGE) {
                            echo "New release unhealthy – rolling back to ${env.PREVIOUS_IMAGE}"
                            runContainer(env.PREVIOUS_IMAGE)
                            waitForHealth(env.CHECK_URL)
                        }
                        error("Smoke test failed for ${env.CHECK_URL}")
                    }
                    sh "curl -s ${env.CHECK_URL}/api/info"
                    sh "curl -s ${env.CHECK_URL}/api/info | grep -q '\"environment\":\"[a-z-]*${params.APP_ENV}\"'"
                }
            }
        }

        stage('Post-deploy UI check') {
            when { expression { !params.SKIP_UI_TESTS } }
            steps {
                // same Selenium journeys, now against the real deployed container
                sh "./mvnw -B failsafe:integration-test failsafe:verify -Dbrowser=htmlunit -Dbase.url=${env.CHECK_URL}"
            }
            post {
                always { junit allowEmptyResults: true, testResults: 'target/failsafe-reports/*.xml' }
            }
        }
    }

    post {
        success {
            echo "Deployed v${env.APP_VERSION} (${env.GIT_SHORT}) to ${params.APP_ENV}: ${env.APP_URL}"
        }
        failure {
            echo 'Pipeline failed. Nothing new was deployed unless the Deploy stage had already run (see rollback logs).'
        }
        always {
            sh "docker ps --filter name=fuel-tracker --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}' || true"
        }
    }
}

// ----------------------------------------------------------------------------- helpers

def runContainer(String image) {
    sh """
        docker rm -f ${CONTAINER} >/dev/null 2>&1 || true
        docker run -d --name ${CONTAINER} --restart unless-stopped \
          --network ${DOCKER_NET} -p ${HOST_PORT}:8080 \
          -e APP_ENV=${params.APP_ENV} \
          -e MAX_PRICE_PER_LITRE=${params.MAX_PRICE_PER_LITRE} \
          -v fuel-data-${params.APP_ENV}:/app/data \
          ${image}
    """
}

def waitForHealth(String url) {
    for (int i = 0; i < 30; i++) {
        if (sh(returnStatus: true, script: "curl -fs ${url}/actuator/health | grep -q '\"status\":\"UP\"'") == 0) {
            echo "Healthy after ~${i * 3}s: ${url}"
            return true
        }
        sleep 3
    }
    return false
}
