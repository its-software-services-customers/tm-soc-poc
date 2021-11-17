#!/bin/bash

VERSION=v0.0.8
OUTPUT_FOLDER=tm-soc-poc

sudo docker run \
    -v $(pwd)/${OUTPUT_FOLDER}:/wip/output \
    -v ${HOME}/.ssh/:/root/.ssh/ \
    -e IASC_VCS_MODE=git \
    -e ENVIRONMENT=nonprod \
    -e IASC_VCS_URL='https://github.com/its-software-services-customers/tm-soc-poc.git' \
    -e IASC_VCS_REF=develop \
    -it gcr.io/its-artifact-commons/iasc:${VERSION} \
    init

#-e IASC_VAULT_SECRETS=${VAULT_FILE} \
#-v ${HOME}/.config/gcloud:/root/.config/gcloud \

sudo chown -R ${USER}:${USER} ${OUTPUT_FOLDER}
