#!/bin/bash

NIFI_VERSION=1.14.0
CFG_FILE=${HOME}/configs/app.conf
chmod 600 ${CFG_FILE}

if [ -f "${CFG_FILE}" ]; then
    set -o allexport; source "${CFG_FILE}"; set +o allexport
else 
    echo "File [${CFG_FILE}] does not exist!!!" | logger -s
    exit 1
fi

# These env variables are defined in the his.conf
# CONTAINERS_LOG_DIR
# OIDC_CLIENT_ID
# OIDC_CLIENT_SECRET

if [ -z "$1" ]; then
    echo "Argument <up|down> is required!!!"
    exit 1
fi

MODE=$1
BASEDIR=$(pwd)
PATH_CERT=${HOME}/certs
WIP_DIR=${HOME}/data
LOG_DIR=${HOME}/logs
DBZ_DIR=${BASEDIR}/debezium
#SRC_CERT=${HOME}/rke-addons/certs
CONNECTOR_NAME=connector-${GROUP}
LOKI_SECRET_FILE=loki-secret.txt
S3_ALIAS=moph-his-gw
LOG_FILE=${LOG_DIR}/actions.log

mkdir -p ${PATH_CERT}
mkdir -p ${WIP_DIR}
mkdir -p ${LOG_DIR}

if [ -f "./mc" ]; then
    echo "Not download mc because it is already exist" | logger -s
else 
    # Install MinIO client
    echo "" | logger -s
    echo "### Downloading MinIO client" | logger -s
    curl -LO https://dl.min.io/client/mc/release/linux-amd64/mc | logger -s
    chmod +x mc
fi

if [[ $MODE =~ ^(down)$ ]]; 
then
    sudo docker-compose down | logger -s
fi

if [[ $MODE =~ ^(up)$ ]]; 
then
    # Auto generate TLS certificate for nginx
    KEYSTORE_PASSWD=123456nosecureneed
    ./gen-certs.bash ${WIP_DIR}/nginx-certs ${KEYSTORE_PASSWD} | logger -s

    HOST_ALLOW=""
    if [[ ${ITS_ENVIRONMENT} =~ ^$ ]]; 
    then
        # This is in production environment only, we will not expose this port
        HOST_ALLOW="127.0.0.1:" #DO NOT remove the ':' from HOST_ALLOW
    else
        echo "ATTENTION!!! - This expose NIFI to the world!!! (be sure setting this on Non-Production only)" | logger -s
        echo "The ITS_ENVIRONMENT environment variable is [${ITS_ENVIRONMENT}]" | logger -s
    fi

    # Generate .env file
    cat << EOF > .env
CONTAINERS_LOG_DIR=${CONTAINERS_LOG_DIR}
WIP_DIR=${WIP_DIR}
LOG_DIR=${LOG_DIR}
BASEDIR=${BASEDIR}
OIDC_CLIENT_ID=${OIDC_CLIENT_ID}
OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}
HOST_ALLOW=${HOST_ALLOW}
NIFI_VERSION=${NIFI_VERSION}
EOF

    sudo docker-compose up -d | logger -s
fi

if [[ $MODE =~ ^(nifi-config)$ ]]; 
then
    export NIFI_VERSION=${NIFI_VERSION}
    ./deploy-nifi-pg.pl | tee ${LOG_DIR}/deploy-nifi.log | logger -s
fi