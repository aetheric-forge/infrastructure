# step-ca dev instance secrets

`password` and `provisioner_password` protect this standalone Docker
step-ca's own intermediate key and JWK provisioner. This is a separate CA
deployment from the cluster's (though it shares the same root of trust via
`platform/core/step-ca/certs/dev/root_ca.crt`), so it does not reuse the
cluster's SOPS-encrypted secrets. Not committed — generate locally:

```bash
openssl rand -base64 32 > password
openssl rand -base64 32 > provisioner_password
chmod 600 password provisioner_password
```
