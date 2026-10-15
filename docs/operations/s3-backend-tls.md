# S3 upstream TLS

The production S3 ingress terminates public TLS and then uses HTTPS to the
all-in-one S3 listener on port 8334. NGINX verifies that upstream certificate
against `seaweedfs-s3-upstream-ca` and the name `s3.int.blackcircuit.ca`.
SeaweedFS mounts the existing cert-manager `seaweedfs-s3-tls` Secret.
The checked-in CA certificate is public trust material, not a private key.

This backend connection must use TLS because SeaweedFS 4.48 evaluates
`aws:SecureTransport` from its own HTTP request TLS state. TLS termination
followed by an HTTP backend makes bucket policies that deny insecure transport
reject otherwise valid S3 requests, including administrative ones. Forwarded
protocol headers do not change that policy condition in this release.

Port 8333 remains available for existing HTTP clients; it does not satisfy a
bucket's TLS condition. This change preserves IAM policy, bucket policy,
existing identities, volumes, and objects. It does not grant anonymous access.

For an existing bootstrap-managed cluster, first add the TLS listener and
certificate mount, expose service port 8334, and wait for the storage rollout.
Then install the upstream CA Secret and change the ingress backend to HTTPS.
Validate scoped and administrative access: list succeeds, an absent object
returns 404, and access to an unrelated bucket remains denied. Retain the
bucket TLS policy rather than removing it to accommodate an HTTP backend.
