#!/bin/bash
set -euo pipefail

kcadm=/opt/keycloak/bin/kcadm.sh
server=http://dev-keycloak:8080
realm=int.aethericforge.ca
client=aetheric-admin

"$kcadm" config credentials --server "$server" --realm master \
    --user platform-admin --password "$KEYCLOAK_ADMIN_PASSWORD"

# int.aethericforge.ca is also created by bootstrap-minio.sh - a docker compose down -v
# wipes Keycloak's Postgres-backed data taking every realm with it, so this can't assume
# out-of-band provisioning any more than that script can. registrationAllowed=false matches
# the settings bootstrap-minio.sh already uses for this realm.
if ! "$kcadm" get "realms/$realm" >/dev/null 2>&1; then
    "$kcadm" create realms -s "realm=$realm" -s enabled=true \
        -s registrationAllowed=false -s verifyEmail=false
fi

client_id=$("$kcadm" get clients -r "$realm" -q "clientId=$client" \
    --fields id --format csv --noquotes | tail -n 1)

client_args=(
    -s enabled=true
    -s publicClient=false
    -s standardFlowEnabled=true
    -s directAccessGrantsEnabled=false
    -s "secret=$KEYCLOAK_AETHERIC_ADMIN_CLIENT_SECRET"
    -s 'redirectUris=["https://app.int.aethericforge.ca/signin-oidc","http://localhost:5103/signin-oidc"]'
    -s 'webOrigins=["https://app.int.aethericforge.ca","http://localhost:5103"]'
)

if [ -z "$client_id" ]; then
    "$kcadm" create clients -r "$realm" -s "clientId=$client" "${client_args[@]}"
else
    "$kcadm" update "clients/$client_id" -r "$realm" "${client_args[@]}"
fi
