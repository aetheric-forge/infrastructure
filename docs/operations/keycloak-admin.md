# Keycloak browser administration

The shared platform administration console is https://sso-admin.int.blackcircuit.ca/admin/master/console/ on nginx-private, with step-ca-int-acme TLS. It uses the existing master-realm administrator accounts.

Both public SSO root pages and legacy /admin/master/console bookmarks redirect to this private console. An internal-network/VPN route and trust in the platform CA are required, as for the existing internal application admin sites.

Public SSO ingress remains tenant-scoped: sso.blackcircuit.ca serves its two BlackCircuit realms, and sso.aethericforge.ca serves only int.aethericforge.ca. Public master realm and other tenant realm paths return 404. The private admin ingress serves /admin, /realms/master, /resources, and the root redirect; tenant realm authentication endpoints are not exposed there.

Keycloak hostname is https://sso.blackcircuit.ca and hostname-admin is https://sso-admin.int.blackcircuit.ca. Master realm frontendUrl is also https://sso-admin.int.blackcircuit.ca, so its browser authentication stays on the private host. Tenant frontendUrls retain their respective public SSO hosts.

The production Keycloak manifest is aligned with the running v2beta1 CR, in-cluster PostgreSQL Service, and existing resource settings. Apply the Keycloak CR and changed ingress resources individually; the broader historical overlay has unrelated Secret generators.
