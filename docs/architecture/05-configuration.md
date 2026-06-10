# Configuration Management

Configuration determines how an Aetheric Forge deployment behaves.

While GitOps manages the desired state of the platform, configuration defines the characteristics of a specific environment before the platform is created.

Examples include:

- Deployment model
- Environment name
- Platform identity
- Repository credentials
- Secret management configuration
- DNS provider configuration

Configuration establishes the foundation upon which bootstrap and GitOps operate.

---

## Core Principle

Configuration defines _what kind of platform_ will be created.

GitOps defines _what the platform should contain_.

```text
Configuration
      │
      ▼
 Bootstrap
      │
      ▼
   GitOps
      │
      ▼
 Platform
```

Configuration is evaluated before the platform exists.

GitOps operates after the platform exists.

---

## Configuration Lifecycle

The configuration process follows a simple workflow:

```text
Collect Inputs
       │
       ▼
make configure
       │
       ▼
Generate .env
       │
       ▼
Bootstrap
       │
       ▼
GitOps
```

The generated configuration becomes the input for bootstrap operations.

---

## Configuration Sources

Aetheric Forge uses several sources of configuration.

### User Input

User-supplied configuration includes:

- Platform name
- Environment name
- Deployment model
- Repository locations
- Credential locations

These values are collected during configuration.

---

### Credential Inputs

Some configuration values reference externally generated credentials.

Examples include:

- AGE private key paths
- Repository SSH private key paths
- RFC2136 TSIG credentials
- External DNS provider API tokens

The platform consumes these credentials but does not generate them automatically.

---

### Generated Configuration

The configuration process produces a local environment file:

```text
.env
```

This file contains the values required by bootstrap tooling and deployment workflows.

The `.env` file becomes the authoritative local configuration source for the deployment.

---

## Deployment Models

Configuration selects the deployment model.

Currently supported models include:

### Local

Local deployments use:

- k3s
- Local BIND9
- RFC2136 DNS updates
- Local infrastructure

This model is intended for:

- Learning
- Development
- Testing
- Small laboratory environments

---

### AWS

AWS deployments use:

- Amazon EKS
- Cloud infrastructure
- Managed networking resources
- Cloud-based platform services

This model is intended for:

- Integration testing
- Production deployments
- Cloud-native operation

---

## Platform Identity

Every deployment has an identity.

Common identity values include:

```text
Platform Name
Environment Name
Deployment Model
```

Examples:

```text
Platform: aetheric-forge
Environment: dev
Model: local
```

or

```text
Platform: aetheric-forge
Environment: production
Model: aws
```

These values influence naming, resource generation, and deployment behavior.

---

## Secret References

Configuration generally stores references to secrets rather than the secrets themselves whenever possible.

Examples:

```text
AGE Private Key Path
SSH Private Key Path
```

The platform uses these references during bootstrap.

This approach reduces duplication and simplifies credential management.

---

## Deployment Isolation

Each Aetheric Forge deployment should maintain its own working directory and configuration.

A typical deployment consists of:

```text
repository/
├── .env
├── scripts/
├── clusters/
└── platform/
```

The `.env` file defines the identity and configuration of that deployment.

Examples might include:

- Development environments
- Laboratory environments
- Testing environments
- Production environments

Each deployment maintains its own repository clone and configuration.

This approach simplifies operations and reduces the risk of accidentally applying configuration intended for one environment to another.

A deployment should be treated as an independent platform instance with its own lifecycle.

---

## Relationship to GitOps

Configuration and GitOps serve different purposes.

Configuration answers:

> What environment am I creating?

GitOps answers:

> What should exist inside that environment?

The two systems complement each other but operate at different stages of the platform lifecycle.

---

## Configuration Changes

Configuration changes generally occur when:

- Creating a new environment
- Changing deployment models
- Rotating credentials
- Updating repository access
- Modifying DNS provider integrations

Routine platform operations should not require frequent configuration changes.

Most operational changes belong in GitOps.

---

## Design Goals

The configuration system is designed to provide:

- Consistent deployment workflows
- Environment reproducibility
- Clear separation of concerns
- Simple bootstrap operations
- Portable environment definitions

Configuration should be predictable, understandable, and easy to recreate.

---

## Summary

Configuration defines the identity and foundational characteristics of an Aetheric Forge deployment.

Bootstrap consumes configuration to create the platform.

GitOps then assumes responsibility for ongoing platform management.

```text
Configuration
      ↓
 Bootstrap
      ↓
   GitOps
      ↓
 Platform Operations
```

Understanding this progression is essential to understanding how Aetheric Forge environments are created and maintained.

---

## Next Steps

Continue with:

- [DNS Architecture](04-dns.md)
