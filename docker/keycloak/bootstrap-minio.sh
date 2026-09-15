#!/bin/bash
set -euo pipefail

kcadm=/opt/keycloak/bin/kcadm.sh
server=http://dev-keycloak:8080
realm=int.aethericforge.ca
client=minio
group=minio-admins
scope=groups

"$kcadm" config credentials --server "$server" --realm master \
    --user platform-admin --password "$KEYCLOAK_ADMIN_PASSWORD"

if ! "$kcadm" get "realms/$realm" >/dev/null 2>&1; then
    "$kcadm" create realms -s "realm=$realm" -s enabled=true \
        -s registrationAllowed=false -s verifyEmail=false
fi

# "groups" client scope + group-membership mapper, so OIDC tokens carry the
# user's Keycloak group memberships — MinIO reads this via
# MINIO_IDENTITY_OPENID_CLAIM_NAME=groups to map group membership to its own policies.
scope_id=$("$kcadm" get client-scopes -r "$realm" -q "name=$scope" \
    --fields id --format csv --noquotes | tail -n 1)

if [ -z "$scope_id" ]; then
    scope_id=$("$kcadm" create client-scopes -r "$realm" -i \
        -s "name=$scope" \
        -s protocol=openid-connect \
        -s 'attributes={"include.in.token.scope":"true","display.on.consent.screen":"false"}')
fi

if ! "$kcadm" get "client-scopes/$scope_id/protocol-mappers/models" -r "$realm" \
        --fields name --format csv --noquotes | grep -qx "$scope"; then
    "$kcadm" create "client-scopes/$scope_id/protocol-mappers/models" -r "$realm" \
        -s "name=$scope" \
        -s protocol=openid-connect \
        -s protocolMapper=oidc-group-membership-mapper \
        -s 'config={"claim.name":"groups","full.path":"false","id.token.claim":"true","access.token.claim":"true","userinfo.token.claim":"true"}'
fi

if ! "$kcadm" get groups -r "$realm" -q "search=$group" | grep -q "\"name\" : \"$group\""; then
    "$kcadm" create groups -r "$realm" -s "name=$group"
fi

client_id=$("$kcadm" get clients -r "$realm" -q "clientId=$client" \
    --fields id --format csv --noquotes | tail -n 1)

client_args=(
    -s enabled=true
    -s publicClient=false
    -s standardFlowEnabled=true
    -s directAccessGrantsEnabled=false
    -s "secret=$MINIO_IDENTITY_OPENID_CLIENT_SECRET"
    -s 'redirectUris=["https://console-dev.int.aethericforge.ca/oauth_callback","http://localhost:9001/oauth_callback"]'
    -s 'webOrigins=["https://console-dev.int.aethericforge.ca","http://localhost:9001"]'
)

if [ -z "$client_id" ]; then
    client_id=$("$kcadm" create clients -r "$realm" -i -s "clientId=$client" "${client_args[@]}")
else
    "$kcadm" update "clients/$client_id" -r "$realm" "${client_args[@]}"
fi

"$kcadm" update "clients/$client_id/default-client-scopes/$scope_id" -r "$realm"
