#!/bin/bash

JDK=java-1.8.0-openjdk
DOCKER_COMPOSE_VERSION=v2.0.1
DOCKER_COMPOSE_PATH=/usr/bin/docker-compose

sudo apt-get -y update

#sudo snap install docker # Using snap will not work with RKE

# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

sudo apt install -y unzip
sudo apt install -y ${JDK}
sudo apt install -y cpan

yes | sudo perl -MCPAN -e 'install JSON'

# Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
    -o ${DOCKER_COMPOSE_PATH}
sudo chmod +x ${DOCKER_COMPOSE_PATH}

sudo groupadd docker
sudo usermod -aG docker ${USER}
#sudo usermod -aG sudo ${USER}