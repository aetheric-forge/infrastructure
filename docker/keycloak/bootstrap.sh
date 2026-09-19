#!/bin/bash
set -euo pipefail

# Creates only the realm and its root provisioner client - not forge-campus's own login
# client, nor the forge-admins group. Those are scoped, per-app resources the provisioner
# creates itself (using this client's credentials) once it has a Keycloak resource provider;
# until then they're created manually. See docker/README.md.
kcadm=/opt/keycloak/bin/kcadm.sh
server=http://dev-keycloak:8080
realm=aethericforge.ca
provisioner_client=forge-campus-provisioner

"$kcadm" config credentials --server "$server" --realm master \
    --user platform-admin --password "$KEYCLOAK_ADMIN_PASSWORD"

if ! "$kcadm" get "realms/$realm" >/dev/null 2>&1; then
    "$kcadm" create realms -s "realm=$realm" -s enabled=true \
        -s registrationAllowed=true -s verifyEmail=false
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

# realm-admin is realm-management's composite admin role - covers clients, groups, users, and
# realm settings in one grant. This client is the provisioner's root credential for this realm,
# so it needs the full set to create/manage everything that used to be created by this script
# directly (forge-campus, forge-admins, ...).
"$kcadm" add-roles -r "$realm" \
    --uusername "service-account-$provisioner_client" \
    --cclientid realm-management \
    --rolename realm-admin
