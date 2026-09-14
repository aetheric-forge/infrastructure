#!/bin/bash
set -euo pipefail

kcadm=/opt/keycloak/bin/kcadm.sh
server=http://dev-keycloak:8080
realm=int.blackcircuit.ca
client=blackcircuit-admin

"$kcadm" config credentials --server "$server" --realm master \
    --user platform-admin --password "$KEYCLOAK_ADMIN_PASSWORD"

# This realm is expected to already exist (created outside this repo) — fail loudly
# rather than silently creating a differently-configured one if it's missing.
if ! "$kcadm" get "realms/$realm" >/dev/null 2>&1; then
    echo "Realm '$realm' does not exist. Expected it to already be provisioned." >&2
    exit 1
fi

client_id=$("$kcadm" get clients -r "$realm" -q "clientId=$client" \
    --fields id --format csv --noquotes | tail -n 1)

client_args=(
    -s enabled=true
    -s publicClient=false
    -s standardFlowEnabled=true
    -s directAccessGrantsEnabled=false
    -s "secret=$KEYCLOAK_BLACKCIRCUIT_ADMIN_CLIENT_SECRET"
    -s 'redirectUris=["https://app.int.blackcircuit.ca/signin-oidc","http://localhost:5102/signin-oidc"]'
    -s 'webOrigins=["https://app.int.blackcircuit.ca","http://localhost:5102"]'
)

if [ -z "$client_id" ]; then
    "$kcadm" create clients -r "$realm" -s "clientId=$client" "${client_args[@]}"
else
    "$kcadm" update "clients/$client_id" -r "$realm" "${client_args[@]}"
fi
