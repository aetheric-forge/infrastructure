#!/bin/bash
set -euo pipefail

kcadm=/opt/keycloak/bin/kcadm.sh
server=http://dev-keycloak:8080
realm=aethericforge.ca
login_client=forge-campus
provisioner_client=forge-campus-provisioner

"$kcadm" config credentials --server "$server" --realm master \
    --user platform-admin --password "$KEYCLOAK_ADMIN_PASSWORD"

if ! "$kcadm" get "realms/$realm" >/dev/null 2>&1; then
    "$kcadm" create realms -s "realm=$realm" -s enabled=true \
        -s registrationAllowed=true -s verifyEmail=false
fi

client_id=$("$kcadm" get clients -r "$realm" -q "clientId=$login_client" \
    --fields id --format csv --noquotes | tail -n 1)

client_args=(
    -s enabled=true
    -s publicClient=false
    -s standardFlowEnabled=true
    -s directAccessGrantsEnabled=false
    -s "secret=$KEYCLOAK_CLIENT_SECRET"
    -s 'redirectUris=["https://aethericforge.ca/*","https://www.aethericforge.ca/*","https://www-dev.aethericforge.ca/*"]'
    -s 'webOrigins=["https://aethericforge.ca","https://www.aethericforge.ca","https://www-dev.aethericforge.ca"]'
)

if [ -z "$client_id" ]; then
    "$kcadm" create clients -r "$realm" -s "clientId=$login_client" "${client_args[@]}"
else
    "$kcadm" update "clients/$client_id" -r "$realm" "${client_args[@]}"
fi

provisioner_id=$("$kcadm" get clients -r "$realm" \
    -q "clientId=$provisioner_client" --fields id --format csv --noquotes | tail -n 1)

provisioner_args=(
    -s enabled=true
    -s publicClient=false
    -s standardFlowEnabled=false
    -s directAccessGrantsEnabled=false
    -s serviceAccountsEnabled=true
    -s "secret=$KEYCLOAK_PROVISIONER_CLIENT_SECRET"
)

if [ -z "$provisioner_id" ]; then
    "$kcadm" create clients -r "$realm" -s "clientId=$provisioner_client" \
        "${provisioner_args[@]}"
else
    "$kcadm" update "clients/$provisioner_id" -r "$realm" \
        "${provisioner_args[@]}"
fi

"$kcadm" add-roles -r "$realm" \
    --uusername "service-account-$provisioner_client" \
    --cclientid realm-management \
    --rolename manage-users \
    --rolename query-users \
    --rolename view-users

if ! "$kcadm" get groups -r "$realm" -q search=forge-admins | grep -q '"name" : "forge-admins"'; then
    "$kcadm" create groups -r "$realm" -s name=forge-admins
fi
