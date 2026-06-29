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

## Running locally

All variables are passed as environment variables so that the same `live/cluster.hcl` works
both locally and in CI without any file changes.

**1. Copy the example env file and fill in your values:**

```bash
cp local.env.example local.env
# edit local.env with your account ID, region, domain, etc.
```

**2. Source it in your shell:**

```bash
source local.env
```

**3. Run Terragrunt:**

```bash
# Plan or apply a single module
cd live/eks/vpc      && terragrunt plan
cd live/eks/cluster  && terragrunt plan

# Plan or apply the full stack in dependency order
cd live/eks && terragrunt run-all plan
cd live/eks && terragrunt run-all apply
```

**4. Finish cluster setup (StorageClass, Flux bootstrap, Traefik):**

After `terragrunt apply` completes, run the post-apply script to mirror what the CI pipeline
does — creates the gp3 StorageClass, the Flux namespaces and cluster-vars ConfigMap, and
bootstraps Flux which then installs Traefik:

```bash
# Full setup including Flux bootstrap (requires GITHUB_TOKEN)
export GITHUB_TOKEN=ghp_...
./scripts/post-apply.sh

# Stop before Flux bootstrap (quick smoke-test of the k8s resources only)
./scripts/post-apply.sh --skip-flux
```

The script validates that `local.env` is sourced, checks cluster access, and exits with a clear
error message if anything is missing.

`local.env` is listed in `.gitignore` and will never be committed. `local.env.example` is the
committed template — keep it in sync when adding new variables.

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
| `INSTANCE_TYPES` | `["t3.medium"]` | JSON array — plain strings cause a Terraform parse error |
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

## kubectl authentication

### In CI (GitHub Actions)

`kubectl` never authenticates via OIDC directly. The chain is:

```
GitHub OIDC token
  → assumes AWS_DEPLOY_ROLE_ARN       (configure-aws-credentials step)
    → aws eks update-kubeconfig       (writes kubeconfig with exec plugin)
      → kubectl                       (calls aws eks get-token using env creds)
        → EKS API server
```

This works automatically because EKS grants `system:masters` to whichever IAM entity
**created the cluster**. Since Terraform runs as `AWS_DEPLOY_ROLE_ARN`, that role is the
cluster creator and has full kubectl access with no additional config.

### Locally (first-time setup)

**1. Update your kubeconfig:**

```bash
aws eks update-kubeconfig --name eks-cluster --region eu-central-1
```

**2. Check which IAM identity is active in your shell:**

```bash
aws sts get-caller-identity
```

**Case A — same identity that ran `terragrunt apply`**

EKS automatically grants `system:masters` to the cluster creator. If `kubectl` still fails with
"server has asked for credentials", the shell is missing the AWS credentials. Source `local.env`
first and retry:

```bash
source local.env
kubectl get nodes -o wide
```

**Case B — different identity (e.g. default profile, different terminal)**

That identity has no RBAC entry yet. Add it using the credentials that created the cluster
(i.e. with `local.env` sourced):

```bash
TARGET_ARN=$(aws sts get-caller-identity --query Arn --output text)

aws eks create-access-entry \
  --cluster-name eks-cluster \
  --region eu-central-1 \
  --principal-arn "$TARGET_ARN" \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name eks-cluster \
  --region eu-central-1 \
  --principal-arn "$TARGET_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

No need to update kubeconfig again — `kubectl get nodes` will work immediately after.

EKS Access Entries are the modern replacement for editing the `aws-auth` ConfigMap (available
on EKS 1.23+). A bad edit to `aws-auth` can lock everyone out of the cluster; Access Entries
are managed via the AWS API and are safe to use.

**Tip — avoid the credentials-not-found problem permanently**

Instead of exporting raw keys in `local.env`, use a named profile in `~/.aws/credentials`:

```ini
[eks-local]
aws_access_key_id     = AKIA…
aws_secret_access_key = …
```

Then in `local.env`:

```bash
export AWS_PROFILE="eks-local"
```

With a named profile, `aws eks get-token` always picks up the right credentials regardless of
which terminal you are in.

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
