# terragrunt-eks

Bootstraps a production-ready EKS cluster with Terragrunt/Terraform and GitOps via Flux CD.

## What gets created

| Layer | What | How |
|---|---|---|
| Networking | 1 VPC, 3 public + 3 private subnets (one per AZ), NAT Gateway | Terraform (vpc module) |
| Compute | EKS cluster + managed node group (configurable instance type) | Terraform (eks module) |
| Addons | vpc-cni, ebs-csi, coredns, kube-proxy, pod-identity | Terraform (eks-addons module) |
| Load balancer | Internet-facing NLB → NodePort 30000 (HTTP) / 30001 (HTTPS) | Terraform (nlb module) |
| Ingress | Traefik v3, NodePort service, Let's Encrypt DNS-01 via Route53 | Flux CD (HelmRelease) |
| GitOps | Flux CD bootstrapped into the cluster, syncing `gitops/` | GitHub Actions |

---

## Prerequisites

- AWS CLI configured with sufficient permissions
- Terraform >= 1.9
- Terragrunt >= 0.67
- Flux CLI (for local troubleshooting)

---

## Step 1 — Bootstrap the remote state backend

Terraform needs an S3 bucket (state storage) and a DynamoDB table (state locking) before any
module can run. These cannot manage themselves, so they are created once with a local-state
Terraform config in `bootstrap/`.

```bash
cd bootstrap
terraform init
terraform apply -var="aws_region=<your-region>"
```

This creates:

- **S3 bucket** `tfstate-{account_id}-{region}` — all Terraform state files are stored here,
  one key per Terragrunt module.
- **DynamoDB table** `tfstate-locks` — holds a single lock row per in-flight Terraform run;
  the row is deleted automatically when the run finishes. Prevents concurrent runs from
  corrupting state.

Both resources are protected with `prevent_destroy = true`. Run this **once per AWS account and
region**. The `bootstrap/terraform.tfstate` produced is a small local file — keep it safe or
re-import the resources if it is ever lost.

---

## Step 2 — Configure GitHub Actions

### AWS OIDC trust (recommended)

The pipeline authenticates to AWS via OIDC — no long-lived access keys needed. Create an IAM
role that trusts the GitHub OIDC provider and has the permissions required to manage VPC, EKS,
IAM, and NLB resources. Set `AWS_DEPLOY_ROLE_ARN` to its ARN (see variables table below).

### GitHub Actions variables

Set these in **Settings → Secrets and variables → Actions → Variables**:

| Variable | Example | Notes |
|---|---|---|
| `AWS_ACCOUNT_ID` | `123456789012` | |
| `AWS_DEFAULT_REGION` | `eu-west-1` | Must match the region used in Step 1 |
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::…:role/github-deploy` | IAM role assumed via OIDC |
| `CLUSTER_NAME` | `my-cluster` | Used as a name prefix for all resources |
| `KUBERNETES_VERSION` | `1.32` | EKS control plane version |
| `INSTANCE_TYPES` | `t3.medium` | Comma-separated for multiple, e.g. `t3.medium,t3.large` |
| `NODE_MIN_SIZE` | `2` | |
| `NODE_MAX_SIZE` | `5` | |
| `NODE_DESIRED_SIZE` | `3` | |
| `VPC_CIDR` | `10.0.0.0/16` | |
| `SINGLE_NAT_GATEWAY` | `false` | Set `true` to reduce cost in non-prod environments |
| `DOMAIN_NAME` | `example.com` | Used by Traefik's Let's Encrypt cert resolver |
| `ROUTE53_ZONE_ID` | `Z1ABC…` | Hosted zone for DNS-01 ACME challenge |
| `GITHUB_ORG` | `your-org` | GitHub org or user that owns this repo |
| `GITHUB_REPO` | `terragrunt-eks` | Repository name |

### Manual approval gate

Create a GitHub environment named **`production`** and add required reviewers:
**Settings → Environments → New environment → `production` → Required reviewers**.

The `apply.yml` workflow targets this environment, so every merge to `main` pauses for human
approval before Terraform runs.

---

## Step 3 — Deploy

Push to a branch and open a pull request — `plan.yml` runs `terragrunt run-all plan` and posts
the output. Once the PR is merged to `main`, the `apply.yml` workflow:

1. Waits for manual approval on the `production` environment.
2. Runs `terragrunt run-all apply` (vpc → cluster → addons → nlb, in dependency order).
3. Updates the local kubeconfig.
4. Runs `flux bootstrap github`, which installs Flux into the cluster and commits the
   `gitops/clusters/production/flux-system/` manifests back to this repo.

Flux then reconciles `gitops/apps/traefik/` and installs Traefik via Helm. On first boot,
Traefik requests a Let's Encrypt certificate using the DNS-01 challenge against the Route53
hosted zone — allow a few minutes for propagation.

---

## Project layout

```
bootstrap/               One-time state backend setup (local state, run manually)
modules/
  vpc/                   VPC, subnets, NAT gateway
  eks/                   EKS cluster and managed node group
  eks-addons/            EKS addons + IRSA roles (VPC CNI, EBS CSI, Traefik)
  nlb/                   Network Load Balancer + target groups + SG rules
live/
  cluster.hcl            Shared variables (read from TF_VAR_* env vars)
  eks/
    vpc/                 Terragrunt root: VPC
    cluster/             Terragrunt root: EKS cluster
    addons/              Terragrunt root: addons (depends on cluster)
    nlb/                 Terragrunt root: NLB (depends on vpc + cluster)
gitops/
  clusters/production/   Flux bootstrap path; apps.yaml points to gitops/apps
  apps/traefik/          Traefik HelmRelease (NodePort, ACME DNS-01, IRSA)
.github/workflows/
  plan.yml               PR → terragrunt run-all plan
  apply.yml              Merge to main → approval gate → apply + flux bootstrap
```
