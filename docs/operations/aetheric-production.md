# Aetheric Forge production

Deployed on 2026-10-06 to blackcircuit-ca-platform-prod through ArgoCD Application aetheric-web.

## Hosts and authentication

- aethericforge.ca and www.aethericforge.ca: nginx-public, le-prod.
- admin.int.aethericforge.ca: nginx-private, step-ca-int-ca.
- sso.aethericforge.ca: nginx-public, le-prod; only /realms/int.aethericforge.ca and /resources.
- sso.blackcircuit.ca: only /realms/blackcircuit.ca, /realms/int.blackcircuit.ca, and /resources.

The public SSO ingress does not expose master or /admin. Use an authenticated Kubernetes port-forward to the Keycloak Service for platform administration. Realm frontend URLs are configured in Keycloak's database; hostname configuration alone does not isolate realms.

Realm int.aethericforge.ca is enabled, requires external SSL, and disables self-registration. Its frontendUrl is https://sso.aethericforge.ca. Existing BlackCircuit realm frontendUrls are https://sso.blackcircuit.ca.

Confidential OIDC client aetheric-admin uses authorization code flow. Its sole callback is https://admin.int.aethericforge.ca/signin-oidc, with logout callback /signout-callback-oidc and web origin https://admin.int.aethericforge.ca. Password grants are disabled. All enabled users in this dedicated realm can authenticate to the admin application; create only intended administrators.

## Provisioned resources

- MongoDB operator users: aetheric-maintenance (readWrite/aetheric-maintenance), aetheric-membership-admin (readWrite/aetheric-membership), aetheric-marketing-admin (readWrite/aetheric-marketing), aetheric-web (read/aetheric-marketing). Authentication databases match their application databases.
- Redis ACL user aetheric-admin is restricted to aetheric-admin:* keys/channels. Existing default credentials are preserved. ACLs reside in /data/users.acl on the Redis PVC. Use ACL SAVE after future ACL changes.
- RabbitMQ user and vhost aetheric-admin; no management tag, permissions limited to that vhost.
- SeaweedFS bucket aethericforge and identity with bucket-scoped Read, Write, List, Tagging actions. The mounted S3 config supports SIGHUP reload.
- Scoped app configuration Secrets and GHCR pull Secret in aetheric-forge; authenticated HTTPS repository Secret in argocd.
- Internal DNS external-dns-aetheric-internal owns int.aethericforge.ca records, using the existing authorized RFC2136 TSIG. kube-dns forwards both internal zones to BIND.
- Admin /data has its own 1Gi PVC. Application outbound trust uses the current production step-ca root ConfigMap.

## Recovery

secrets/prod/aetheric-production.enc.yaml is a SOPS-encrypted recovery bundle using the existing ArgoCD age identity. It contains application configuration, pull/repository credentials, Mongo password Secrets, the updated SeaweedFS identity config, and redis-acl-backup. It is deliberately not automatically applied by an application's Kustomization.

With the existing age key available in SOPS_AGE_KEY_FILE:

```sh
sops --decrypt secrets/prod/aetheric-production.enc.yaml | kubectl apply -f -
kubectl patch mongodbcommunity forge-mongo -n forge-mongo --type=merge --patch-file platform/services/forge-mongo/overlays/prod/aetheric-users.merge.json
```

Restore /data/users.acl from the redis-acl-backup Secret before starting Redis on a replacement/empty PVC. An empty ACL file must never be used. Keycloak realm/client state lives in its existing PostgreSQL database and follows the platform database backup process. Redis and admin PVC data require their existing volume backup process; the encrypted bundle is not a database or volume backup.

The ArgoCD Application manifest is in aetheric-forge/aetheric-web-k8s/argocd/application.yaml. Production uses pinned v2.0.0 image digests. Provision Secrets first, then apply the Application.

## Validation

Both applications report Ready and ArgoCD reports Synced/Healthy. Public site / and /projects return 200 on both hosts. The internal admin HTTPS route redirects to the Aetheric realm/client. Correct-host discovery endpoints return 200 with matching issuers; cross-tenant realms and public master return 404. Website realm paths return 404. S3 read/write succeeds within the application bucket and access to velero is denied. Redis application access succeeds after restart and BlackCircuit key access is denied.

An end-to-end interactive login requires a user account in the new realm. Provisioning jobs require a worker attached to the aetheric-admin RabbitMQ vhost; no such worker was deployed as part of this website deployment.
