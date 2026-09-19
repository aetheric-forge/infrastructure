#!/bin/bash
set -euo pipefail

# Creates only the int.aethericforge.ca realm and its root provisioner client - not the
# aetheric-admin or minio OIDC clients, the "groups" client scope/mapper, or the minio-admins
# group. Those are scoped, per-app resources the provisioner creates itself (using this
# client's credentials) once it has a Keycloak resource provider; until then they're created
# manually. See docker/README.md. Replaces bootstrap-aetheric-admin.sh and bootstrap-minio.sh,
# which independently (and redundantly) each bootstrapped this same realm.
kcadm=/opt/keycloak/bin/kcadm.sh
server=http://dev-keycloak:8080
realm=int.aethericforge.ca
provisioner_client=internal-provisioner

"$kcadm" config credentials --server "$server" --realm master \
    --user platform-admin --password "$KEYCLOAK_ADMIN_PASSWORD"

if ! "$kcadm" get "realms/$realm" >/dev/null 2>&1; then
    "$kcadm" create realms -s "realm=$realm" -s enabled=true \
        -s registrationAllowed=false -s verifyEmail=false
fi

provisioner_id=$("$kcadm" get clients -r "$realm" \
    -q "clientId=$provisioner_client" --fields id --format csv --noquotes | tail -n 1)

provisioner_args=(
    -s enabled=true
    -s publicClient=false
    -s standardFlowEnabled=false
    -s directAccessGrantsEnabled=false
    -s serviceAccountsEnabled=true
    -s "secret=$KEYCLOAK_INTERNAL_PROVISIONER_CLIENT_SECRET"
)

if [ -z "$provisioner_id" ]; then
    "$kcadm" create clients -r "$realm" -s "clientId=$provisioner_client" \
        "${provisioner_args[@]}"
else
    "$kcadm" update "clients/$provisioner_id" -r "$realm" \
        "${provisioner_args[@]}"
fi

# Broad realm-management grant - this client is the provisioner's root credential for this
# realm, so it needs enough to create/manage the clients, client scopes, groups, and users
# that used to be created by the two scripts this one replaces.
"$kcadm" add-roles -r "$realm" \
    --uusername "service-account-$provisioner_client" \
    --cclientid realm-management \
    --rolename manage-clients \
    --rolename view-clients \
    --rolename manage-users \
    --rolename query-users \
    --rolename view-users \
    --rolename manage-realm
