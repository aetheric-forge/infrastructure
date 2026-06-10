# Local Development: k3s Cluster

This guide provisions the Kubernetes cluster used by the Local Development deployment model.

Aetheric Forge uses k3s as its recommended local Kubernetes distribution due to its simplicity, low resource requirements, and suitability for laboratory and educational environments.

---

## Objectives

At the end of this guide you will have:

- A functioning k3s cluster
- kubectl access
- A verified Kubernetes environment
- A platform ready for Aetheric Forge bootstrap

---

## System Requirements

Minimum recommended specifications:

- 4 CPU cores
- 8 GB RAM
- 50 GB available storage

Supported operating systems:

- Ubuntu Server LTS
- Debian
- Other Linux distributions may work but are not officially documented.

---

## Install k3s

Install k3s using the official installation method:

```bash
curl -sfL https://get.k3s.io | sh -
```

Verify installation:

```bash
sudo systemctl status k3s
```

---

## Configure kubectl Access

Copy the cluster configuration:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

Verify cluster connectivity:

```bash
kubectl get nodes
```

Expected output:

```text
NAME      STATUS   ROLES                  AGE
hostname  Ready    control-plane,master
```

---

## Verify Core Components

Confirm that system components are healthy:

```bash
kubectl get pods -A
```

CoreDNS and Traefik should report healthy status.

---

## Next Step

Continue to:

- Local Development DNS Configuration
