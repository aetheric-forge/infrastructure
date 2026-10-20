#!/usr/bin/env bash
# Registers Grafana with the cluster's Keycloak: the internal realm (created if
# missing), the grafana OIDC client Grafana's generic OAuth login uses, a
# groups claim, and the groups that map to Grafana roles:
#   grafana-admins  -> Admin
#   grafana-viewers -> Viewer
# Anyone in neither group is refused (see GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT).
# Safe to rerun; existing objects are updated in place.
#
# Run after bootstrap-secrets.sh (which creates monitoring/grafana-oauth) and
# once Keycloak is up. Add people to the groups in the Keycloak UI.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/paths.sh"
source "$ROOT_DIR/.env"

: "${INTERNAL_DOMAIN:?INTERNAL_DOMAIN must be set}"
: "${EXTERNAL_DOMAIN:?EXTERNAL_DOMAIN must be set}"

secret_value() {
	kubectl get secret -n "$1" "$2" -o "jsonpath={.data.$3}" | base64 -d
}

admin_user=$(secret_value keycloak-system forge-keycloak-admin username)
admin_password=$(secret_value keycloak-system forge-keycloak-admin password)
client_secret=$(secret_value monitoring grafana-oauth GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET)

# Values go in through stdin so no password appears in a process listing.
kubectl exec -i -n keycloak-system forge-keycloak-0 -- bash -s <<EOF
set -euo pipefail

kcadm() { /opt/keycloak/bin/kcadm.sh "\$@" --config /tmp/kcadm-grafana.config; }

realm='${INTERNAL_DOMAIN}'
client_id=grafana
grafana_url='https://grafana.${INTERNAL_DOMAIN}'

kcadm config credentials --server 'https://sso.${EXTERNAL_DOMAIN}' --realm master \\
	--user '${admin_user}' --password '${admin_password}'

if ! kcadm get "realms/\$realm" >/dev/null 2>&1; then
	kcadm create realms -s "realm=\$realm" -s enabled=true \\
		-s registrationAllowed=false -s verifyEmail=false
fi

client_args=(
	-s enabled=true
	-s publicClient=false
	-s standardFlowEnabled=true
	-s directAccessGrantsEnabled=false
	-s serviceAccountsEnabled=false
	-s "redirectUris=[\"\$grafana_url/login/generic_oauth\"]"
	-s "webOrigins=[\"\$grafana_url\"]"
	-s 'attributes."pkce.code.challenge.method"=S256'
	-s 'secret=${client_secret}'
)

id=\$(kcadm get clients -r "\$realm" -q "clientId=\$client_id" --fields id --format csv --noquotes | tail -n 1)
if [ -z "\$id" ]; then
	kcadm create clients -r "\$realm" -s "clientId=\$client_id" "\${client_args[@]}"
	id=\$(kcadm get clients -r "\$realm" -q "clientId=\$client_id" --fields id --format csv --noquotes | tail -n 1)
else
	kcadm update "clients/\$id" -r "\$realm" "\${client_args[@]}"
fi

mappers=\$(kcadm get "clients/\$id/protocol-mappers/models" -r "\$realm" --fields name --format csv --noquotes)

# Plain group names (no leading /), matching the role mapping in grafana-oidc.
if ! grep -qx groups <<<"\$mappers"; then
	kcadm create "clients/\$id/protocol-mappers/models" -r "\$realm" \\
		-s name=groups -s protocol=openid-connect \\
		-s protocolMapper=oidc-group-membership-mapper \\
		-s 'config."claim.name"=groups' -s 'config."full.path"=false' \\
		-s 'config."id.token.claim"=true' -s 'config."access.token.claim"=true' \\
		-s 'config."userinfo.token.claim"=true'
fi

for group in grafana-admins grafana-viewers; do
	if ! kcadm get groups -r "\$realm" --fields name --format csv --noquotes | grep -qx "\$group"; then
		kcadm create groups -r "\$realm" -s "name=\$group"
	fi
done

rm -f /tmp/kcadm-grafana.config
echo "[Forge] \$realm: client \$client_id and groups grafana-admins, grafana-viewers ready"
EOF
