# Quick Start

This guide walks through the fastest path to deploying an Aetheric Forge GitOps control plane.

The objective is to provision infrastructure, establish administrative access, and deploy the GitOps platform with minimal manual intervention.

## Prerequisites

Before starting, ensure you have:

- AWS credentials configured
- Pulumi installed
- Python 3.11 or later
- kubectl installed
- SOPS and KSOPS installed
- Access to the target Git repository

## Step 1: Configure Infrastructure

Navigate to the Pulumi deployment directory:

```bash
cd scripts/pulumi
pip install -r requirements.txt
pulumi stack select dev
```

Configure bootstrap inputs and deploy infrastructure.

## Step 2: Establish Administrative Access

Configure WireGuard connectivity to the environment.

Verify cluster access:

```bash
kubectl get nodes
```

Successful node discovery confirms administrative connectivity.

## Step 3: Deploy Platform Components

Deploy the platform phase:

```bash
DEPLOY_PHASE=platform ENVIRONMENT=dev ./scripts/deploy-all.sh
```

This installs:

- Argo CD
- ingress-nginx
- MetalLB
- cert-manager
- step-ca
- DNS providers

## Step 4: Verify Operation

Confirm:

- Nodes are Ready
- Argo CD is Healthy
- Applications synchronize successfully
- DNS records reconcile correctly
- Certificates are issued successfully

## Next Steps

Continue with:

- Architecture Overview
- Bootstrap Process
- GitOps Workflow
- Operations Guide
