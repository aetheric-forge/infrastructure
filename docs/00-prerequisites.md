# Local Development: Prerequisites

This guide installs the tools required for a local Aetheric Forge deployment.

The examples in subsequent guides assume these tools are available.

---

## Supported Platform

The local deployment path is documented for:

- Ubuntu Server LTS
- Debian

Other Linux distributions may work but are not currently documented.

---

## Update Package Metadata

```bash
sudo apt update
```

---

## Install Core Utilities

```bash
sudo apt install -y \
    curl \
    git \
    make \
    jq \
    vim
```

---

## Install AGE

AGE is used by SOPS for secret encryption.

```bash
sudo apt install -y age
```

Verify:

```bash
age --version
```

---

## Install BIND Utilities

RFC2136 TSIG credentials are generated using BIND utilities.

```bash
sudo apt install -y bind9-utils
```

Verify:

```bash
tsig-keygen -h
```

---

## Install kubectl

Install the Kubernetes command-line client.

Refer to the Kubernetes installation documentation appropriate for your operating system.

Verify:

```bash
kubectl version --client
```

---

## Install Helm

Install Helm using the official installation method.

Verify:

```bash
helm version
```

---

## Install SOPS

Install Mozilla SOPS.

Verify:

```bash
sops --version
```

---

## Install Kustomize

Install Kustomize.

Verify:

```bash
kustomize version
```

---

## Verify Tooling

The following commands should execute successfully:

```bash
git --version
make --version
age --version
kubectl version --client
helm version
sops --version
kustomize version
```

---

## Next Step

Continue to:

- Local Development: k3s Cluster
