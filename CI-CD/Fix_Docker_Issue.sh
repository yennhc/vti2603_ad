#!/bin/bash

mkdir -p ~/jenkins-docker
cd ~/jenkins-docker

vim Dockerfile
###########################################
FROM jenkins/jenkins:lts-jdk21

USER root

RUN apt-get update \
    && apt-get install -y docker.io \
    && rm -rf /var/lib/apt/lists/*

USER jenkins
###########################################

docker build -t jenkins-with-docker .

#Verify:
docker run --rm jenkins-with-docker docker --version

#Recreate Jenkins with the Docker socket
docker stop jenkins
docker rename jenkins jenkins-old

#Then determine the Docker socket group ID on the host:
stat -c '%g' /var/run/docker.sock

#Start the new Jenkins container using the same persistent volume:
docker run -d \
  --name jenkins \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --group-add $(stat -c '%g' /var/run/docker.sock) \
  jenkins-with-docker

#Verify Docker from inside Jenkins
docker exec -it jenkins bash

whoami
docker --version
docker version
docker ps

