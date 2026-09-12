# Local dev TLS cert for `*.int.aethericforge.ca`

`int-aethericforge.crt`/`.key` are self-signed placeholders for the internal
dev hostnames (`rabbitmq-dev`, `console-dev`, `s3-dev`, `ca-dev`) until the
step-ca ACME server is wired up to issue real internal certs. Not committed —
regenerate locally:

```bash
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout int-aethericforge.key -out int-aethericforge.crt \
  -days 397 -config int-aethericforge.cnf -extensions v3_req
```
