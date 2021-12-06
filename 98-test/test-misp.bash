#!/bin/bash

URL=https://10.141.98.175/attributes/restSearch
KEY=<change-this>

curl -v -k \
    --header "Authorization: ${KEY}" \
    --header "Accept: application/json" \
    --header "Content-Type: application/json" ${URL} \
    --data @body.json
