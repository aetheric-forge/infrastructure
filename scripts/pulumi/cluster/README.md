 # Aetheric Forge Kubernetes cluster

This Pulumi project provisions the platform Kubernetes cluster. It supports AWS
EKS, Civo Kubernetes, GKE, and a local pre-existing kubeconfig.

## GKE production single-worker rollout

The production stack keeps the regional GKE control plane and runs one worker in
`GCP_ZONE`. The `singleZoneWorkers` stack setting pins the worker pool at one
node, overriding `NODE_MIN_SIZE`, `NODE_MAX_SIZE` and `NODE_DESIRED_SIZE`.
The node machine type and disk settings still come from the existing environment.

For an existing multi-zone deployment, complete the workload changes before
reducing the worker pool:

1. Confirm recoverable backups and inventory all bound persistent volumes and
   their zones. Choose `GCP_ZONE` based on the volumes the workloads will keep.
   Migrate any retained zonal disks outside that zone before removing workers.
2. Reduce CloudNativePG to one instance and verify that the remaining primary is
   healthy. Verify that its data and any WAL volumes are in the retained zone.
3. Migrate RabbitMQ to a one-broker cluster. The pinned RabbitMQ Cluster Operator
   v2.21.1 rejects an in-place change from three replicas to one. Plan a broker
   cutover that preserves definitions and accounts for queued messages before
   retiring the old cluster.
4. Run `pulumi preview --stack prod` with the deployment environment loaded.
   Confirm that the planned worker-pool change preserves the regional control
   plane. After the worker reduction, check for pending pods and verify storage,
   database, broker and ingress health. Worker maintenance can interrupt service
   in this configuration.

## Civo

Set `CLOUD=civo` in the repository `.env` together with `CIVO_REGION`,
`CIVO_NODE_SIZE`, and `CIVO_NODE_COUNT`. Authenticate without committing the
token:

```bash
export CIVO_TOKEN="..."
```

The Civo deployment creates a dedicated network, firewall, and managed k3s
cluster. Civo's default marketplace applications are reconciled after creation
before this repository installs ingress-nginx.

Do not create these resources manually in the Civo dashboard; Pulumi owns their
lifecycle.

## Legacy template notes

 A minimal Pulumi template for provisioning a single AWS S3 bucket using Python.

 ## Overview

 This template provisions an S3 bucket (`pulumi_aws.s3.BucketV2`) in your AWS account and exports its ID as an output. It’s an ideal starting point when:
  - You want to learn Pulumi with AWS in Python.
  - You need a barebones S3 bucket deployment to build upon.
  - You prefer a minimal template without extra dependencies.

 ## Prerequisites

 - An AWS account with permissions to create S3 buckets.
 - AWS credentials configured in your environment (for example via AWS CLI or environment variables).
 - Python 3.6 or later installed.
 - Pulumi CLI already installed and logged in.

 ## Getting Started

 1. Generate a new project from this template:
    ```bash
    pulumi new aws-python
    ```
 2. Follow the prompts to set your project name and AWS region (default: `us-east-1`).
 3. Change into your project directory:
    ```bash
    cd <project-name>
    ```
 4. Preview the planned changes:
    ```bash
    pulumi preview
    ```
 5. Deploy the stack:
    ```bash
    pulumi up
    ```
 6. Tear down when finished:
    ```bash
    pulumi destroy
    ```

 ## Project Layout

 After running `pulumi new`, your directory will look like:
 ```
 ├── __main__.py         # Entry point of the Pulumi program
 ├── Pulumi.yaml         # Project metadata and template configuration
 ├── requirements.txt    # Python dependencies
 └── Pulumi.<stack>.yaml # Stack-specific configuration (e.g., Pulumi.dev.yaml)
 ```

 ## Configuration

 This template defines the following config value:

 - `aws:region` (string)
   The AWS region to deploy resources into.
   Default: `us-east-1`

 View or update configuration with:
 ```bash
 pulumi config get aws:region
 pulumi config set aws:region us-west-2
 ```

 ## Outputs

 Once deployed, the stack exports:

 - `bucket_name` — the ID of the created S3 bucket.

 Retrieve outputs with:
 ```bash
 pulumi stack output bucket_name
 ```

 ## Next Steps

 - Customize `__main__.py` to add or configure additional resources.
 - Explore the Pulumi AWS SDK: https://www.pulumi.com/registry/packages/aws/
 - Break your infrastructure into modules for better organization.
 - Integrate into CI/CD pipelines for automated deployments.

 ## Help and Community

 If you have questions or need assistance:
 - Pulumi Documentation: https://www.pulumi.com/docs/
 - Community Slack: https://slack.pulumi.com/
 - GitHub Issues: https://github.com/pulumi/pulumi/issues

 Contributions and feedback are always welcome!
