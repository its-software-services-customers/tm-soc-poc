#!/bin/bash

CERT_DIR=$1
KEY_PASSWORD=$2

ROOT_KEY=ca.key
ROOT_CERT=ca.crt
EXT_FILE=ca.ext

SERVER_KEY=my-server.key
SERVER_CERT=my-server.crt
SERVER_KEY_CERT=my-server-key-crt.pem
SERVER_EXT_FILE=my-server.ext
SERVER_CSR=my-server.csr
SERVER_PCK=my-server-keystore.p12

mkdir -p ${CERT_DIR}
#sudo chown ${CERT_DIR} ${USER}:${USER}

############## ROOT ##############
cat << EOF > ${CERT_DIR}/${EXT_FILE}
[req]
distinguished_name = req_distinguished_name

req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = TH
ST = Bangkok
L = Bangkok
O = ICT
OU = MOPH
CN = ROOT

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @san_names

[san_names]
DNS.1 = root.moph.cluster.local
EOF

openssl genrsa -out ${CERT_DIR}/${ROOT_KEY} 2048
openssl req -x509 -new -nodes \
    -key ${CERT_DIR}/${ROOT_KEY} -sha256 -days 1825 -out ${CERT_DIR}/${ROOT_CERT} \
    -config ${CERT_DIR}/${EXT_FILE}


############## SERVER ##############
cat << EOF > ${CERT_DIR}/${SERVER_EXT_FILE}
[req]
distinguished_name = req_distinguished_name

req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = TH
ST = Bangkok
L = Bangkok
O = ICT
OU = MOPH
CN = GATEWAY

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @san_names

[san_names]
DNS.1 = his-gw.moph.cluster.local
EOF

# Generate key
openssl genrsa -out ${CERT_DIR}/${SERVER_KEY} 2048

# Generate CSR
openssl req -key ${CERT_DIR}/${SERVER_KEY} \
    -new -out ${CERT_DIR}/${SERVER_CSR} \
    -config ${CERT_DIR}/${SERVER_EXT_FILE}

openssl x509 -req -CA ${CERT_DIR}/${ROOT_CERT} \
    -CAkey ${CERT_DIR}/${ROOT_KEY} \
    -in ${CERT_DIR}/${SERVER_CSR} -out ${CERT_DIR}/${SERVER_CERT} -days 3650 -CAcreateserial

# Generate keystore
cat ${CERT_DIR}/${SERVER_KEY} ${CERT_DIR}/${SERVER_CERT} > ${CERT_DIR}/${SERVER_KEY_CERT}
openssl pkcs12 -export -in ${CERT_DIR}/${SERVER_KEY_CERT} -out ${CERT_DIR}/${SERVER_PCK} -name tls -noiter -nomaciter -passout pass:${KEY_PASSWORD}
