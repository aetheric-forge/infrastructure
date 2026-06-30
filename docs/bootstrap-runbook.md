# Bootstrap Runbook

This runbook provides step-by-step instructions for bootstrapping the platform from scratch—either locally or on AWS. Follow the sequence carefully to ensure a successful and secure deployment.

## Prerequisites
- Ensure you have read and completed steps in `docs/00-prerequisites.md` and any other relevant environment setup documentation.
- Have the following ready:
  - TSIG, SSH, and SOPS keys
  - Cloudflare API token (for DNS management)
  - For AWS: Working AWS CLI and credentials
  - For Local: k3s installed (see `docs/local/k3s.md`)

## High-Level Bootstrap Steps

### 1. Initial Configuration
```sh
make configure
```
- This command will require you to provide/generate:
  - TSIG key
  - SSH key
  - SOPS key
  - Cloudflare API token
- If any step or value is unclear, refer to relevant code, Makefile, or documentation sections.

### 2. Cluster Creation
**Local:**
```sh
make create universe
```
- Assumes k3s is running (see `docs/local/k3s.md`).

**AWS:**
```sh
make create universe
```
- Requires that your AWS CLI is authenticated.

### 3. Monitor Cluster Boot
Use any of the following to watch resource creation:
```sh
k9s
# or
kubectl get all -A -w
```

### 4. Keycloak Initial Admin Login
- Fetch the temporary admin credentials from Kubernetes:
```sh
kubectl get secret keycloak-initial-admin -n keycloak-system -o yaml
```
  - Decode and log in to Keycloak using the provided credentials.

### 5. Secure Keycloak
- Create a **root user**.
- Delete the **temporary admin user**.
  - This is critical for security.

### 6. Internal Realm
- Create a new realm named `internal` in Keycloak.
- Create a root user for the `internal` realm.

### 7. Keycloak Groups
- Inside the `internal` realm, create the following groups:
  - minio-admins
  - argocd-admins

### 8. Client Scope for Groups
- Add a default client scope called `groups` to the `internal` realm for OIDC.

### 9. OIDC Clients
- Create OIDC clients for:
  - ArgoCD
  - Minio
- Obtain client secrets from Kubernetes:
```sh
kubectl get secret <client-name> -n <namespace> -o yaml
```

### 10. Minio Admin Setup
- Login to Minio using OIDC.
- Update the `minio-admins` policy to match the `consoleAdmin` policy (the initial `mc` image does not set this correctly).
- Log out of Minio and log back in to confirm changes.

### 11. S3 Buckets
- In Minio, create these buckets:
  - `velero`
  - `forge-db-dev`

### 12. S3 Policies
- Create Minio policies for both buckets allowing standard operations for their respective purposes.

### 13. S3 Users
- Create users for Velero and Forge:
  - `velero`
  - `forge-db-dev`
- Generate and securely store S3 credentials for both users (credentials are stored in Kubernetes secrets).

### 14. Velero Integration
- Verify that the backupstoragelocation is now available for Velero.
  - You can check this in the Velero namespace:
```sh
kubectl get backupstoragelocation -n velero
```

### 15. Service Verification
- Confirm successful startup of all platform services:
  - RabbitMQ
  - MongoDB
  - Redis

### 16. Tag the Release
- When all checks are green, you may tag this state as `v1.0`.

---

For troubleshooting or further reference, consult the codebase (see scripts and manifests under deployment, bootstrap, or Makefile targets) and the architecture documents in `docs/architecture/`.