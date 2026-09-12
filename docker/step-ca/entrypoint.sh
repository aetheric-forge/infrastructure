#!/bin/sh
set -eu

mkdir -p /home/step/certs /home/step/config /home/step/db /home/step/secrets

if [ ! -f /home/step/config/ca.json ]; then
    step ca init \
        --name "${STEP_CA_NAME}" \
        --dns "${STEP_CA_DNS}" \
        --root /run/secrets/step-ca-root-ca/root_ca.crt \
        --key /run/secrets/step-ca-root-ca/root_ca.key \
        --address ":9000" \
        --provisioner "${STEP_CA_PROVISIONER}" \
        --password-file /run/secrets/step-ca/password \
        --provisioner-password-file /run/secrets/step-ca/provisioner_password \
        --deployment-type standalone \
        --acme
fi

exec step-ca /home/step/config/ca.json --password-file /run/secrets/step-ca/password
