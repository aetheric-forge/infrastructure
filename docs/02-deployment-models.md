# Deployment Models

Aetheric Forge supports multiple deployment models, each designed for a different stage of learning, development, and operation.

Before proceeding with installation, review the available deployment models and select the one that best matches your objectives.

---

## Choosing a Deployment Model

Use the following guidelines:

| Goal                                | Recommended Model |
| ----------------------------------- | ----------------- |
| Learn GitOps and platform concepts  | Local Development |
| Develop and test platform changes   | Local Development |
| Validate cloud deployment workflows | AWS Development   |
| Operate a production environment    | Production        |

Most users should begin with Local Development before deploying to cloud infrastructure.

---

## Local Development

Local Development provides a complete Aetheric Forge environment on local hardware using k3s.

This model is intended for:

- Learning Kubernetes fundamentals
- Exploring GitOps workflows
- Platform development
- Functional testing
- Educational environments
- Small laboratory deployments

### Characteristics

- Single-node deployment
- k3s Kubernetes distribution
- Local RFC2136 DNS authority
- Local BIND9 server
- Minimal infrastructure requirements
- Fast deployment and teardown

### Advantages

- No cloud costs
- Rapid iteration
- Simple troubleshooting
- Ideal for experimentation

### Limitations

- Not highly available
- Limited scalability
- Not intended for production workloads

### Documentation

- Local Installation
- k3s Installation
- BIND9 Installation
- Local Bootstrap

---

## AWS Development

AWS Development deploys Aetheric Forge into Amazon EKS using infrastructure managed through Pulumi.

This model is intended for:

- Infrastructure validation
- Platform integration testing
- Cloud-native development
- Environment promotion testing

### Characteristics

- Amazon EKS
- Pulumi-managed infrastructure
- GitOps-managed platform services
- WireGuard administrative access
- Public and private DNS integration

### Advantages

- Mirrors production architecture
- Validates cloud deployment workflows
- Supports realistic testing scenarios

### Limitations

- AWS costs apply
- Additional operational complexity
- Requires cloud account management

### Documentation

- AWS Prerequisites
- Infrastructure Provisioning
- WireGuard Configuration
- AWS Bootstrap

---

## Production

Production deployments provide a complete operational GitOps platform suitable for organizational workloads.

Production environments emphasize stability, security, reproducibility, and operational simplicity.

### Characteristics

- Cloud-hosted Kubernetes
- Automated GitOps reconciliation
- Internal and public DNS separation
- Automated certificate management
- Controlled administrative access
- Infrastructure-as-Code provisioning

### Recommended Use Cases

- Small organizations
- Educational institutions
- Research environments
- Community infrastructure
- Self-hosted platform operations

### Operational Requirements

Production deployments should include:

- Backup and recovery procedures
- Monitoring and alerting
- Secret management processes
- Operational documentation
- Change management workflows

### Documentation

- Production Architecture
- Operations Guide
- Disaster Recovery
- Security and Access Control

---

## Migration Path

Aetheric Forge is designed to support a progressive learning and adoption path.

A typical journey follows:

```text
Local Development
        ↓
AWS Development
        ↓
Production
```

Users are encouraged to become comfortable with local deployment and GitOps workflows before operating cloud-hosted environments.

---

## Next Steps

Once you have selected a deployment model, continue with the appropriate installation and bootstrap documentation.

For most users, the recommended next step is:

- Local Development Installation
