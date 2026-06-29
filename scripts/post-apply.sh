#!/usr/bin/env bash
# post-apply.sh
#
# Mirrors the kubectl + Flux steps from .github/workflows/apply.yml.
# Run this after `terragrunt run-all apply` to finish cluster setup locally.
#
# Prerequisites:
#   source local.env          (AWS credentials + TF_VAR_* must be in the environment)
#   aws, kubectl, flux, helm  (CLIs must be on PATH)
#
# Usage:
#   ./scripts/post-apply.sh
#   ./scripts/post-apply.sh --skip-flux   (stops before Flux bootstrap; useful for quick tests)

set -euo pipefail

SKIP_FLUX=false
for arg in "$@"; do
  [[ "$arg" == "--skip-flux" ]] && SKIP_FLUX=true
done

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Validate environment ───────────────────────────────────────────────────────
[[ -z "${AWS_DEFAULT_REGION:-}"    ]] && error "AWS_DEFAULT_REGION is not set. Run: source local.env"
[[ -z "${TF_VAR_cluster_name:-}"   ]] && error "TF_VAR_cluster_name is not set. Run: source local.env"
[[ -z "${TF_VAR_domain_name:-}"    ]] && error "TF_VAR_domain_name is not set. Run: source local.env"
[[ -z "${TF_VAR_route53_zone_id:-}" ]] && error "TF_VAR_route53_zone_id is not set. Run: source local.env"

for cmd in aws kubectl flux; do
  command -v "$cmd" &>/dev/null || error "'$cmd' not found on PATH"
done

CLUSTER_NAME="$TF_VAR_cluster_name"
REGION="$AWS_DEFAULT_REGION"

# ── 1. Update kubeconfig ───────────────────────────────────────────────────────
info "Updating kubeconfig for cluster '$CLUSTER_NAME' in '$REGION'..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

info "Verifying cluster access..."
kubectl cluster-info --request-timeout=10s \
  || error "Cannot reach the cluster. Check your IAM identity (aws sts get-caller-identity) and README section 'kubectl authentication'."

# ── 2. gp3 StorageClass ────────────────────────────────────────────────────────
info "Creating gp3 StorageClass..."
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
  encrypted: "true"
EOF

info "Removing default annotation from gp2..."
kubectl patch storageclass gp2 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' \
  --ignore-not-found

# ── 3. Namespaces ──────────────────────────────────────────────────────────────
info "Creating namespaces..."
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace traefik     --dry-run=client -o yaml | kubectl apply -f -

# ── 4. cluster-vars ConfigMap ──────────────────────────────────────────────────
info "Reading Traefik IRSA role ARN from Terragrunt output..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAEFIK_ROLE_ARN=$(
  cd "$SCRIPT_DIR/../live/eks/addons" \
  && terragrunt output -raw traefik_role_arn 2>/dev/null
) || error "Could not read traefik_role_arn output. Has 'terragrunt apply' been run for the addons module?"

info "Creating cluster-vars ConfigMap in flux-system..."
kubectl create configmap cluster-vars \
  --namespace flux-system \
  --from-literal=TRAEFIK_ROLE_ARN="$TRAEFIK_ROLE_ARN" \
  --from-literal=AWS_REGION="$REGION" \
  --from-literal=DOMAIN_NAME="$TF_VAR_domain_name" \
  --from-literal=ROUTE53_ZONE_ID="$TF_VAR_route53_zone_id" \
  --dry-run=client -o yaml | kubectl apply -f -

# ── 5. Flux bootstrap ──────────────────────────────────────────────────────────
if [[ "$SKIP_FLUX" == true ]]; then
  warn "--skip-flux set: stopping before Flux bootstrap."
  warn "Traefik will NOT be installed. Re-run without --skip-flux to complete setup."
  exit 0
fi

[[ -z "${GITHUB_TOKEN:-}" ]] && error "GITHUB_TOKEN is not set. Export it before running this script:\n  export GITHUB_TOKEN=ghp_..."
[[ -z "${TF_VAR_github_org:-}"  ]] && error "TF_VAR_github_org is not set. Run: source local.env"
[[ -z "${TF_VAR_github_repo:-}" ]] && error "TF_VAR_github_repo is not set. Run: source local.env"

info "Bootstrapping Flux..."
flux bootstrap github \
  --owner="$TF_VAR_github_org" \
  --repository="$TF_VAR_github_repo" \
  --branch=main \
  --path="gitops/clusters/production" \
  --personal=false \
  --token-auth=false

info "Waiting for Flux Kustomizations to reconcile..."
flux reconcile kustomization flux-system --with-source --timeout=5m
flux reconcile kustomization apps         --timeout=5m || true

info "Checking Traefik HelmRelease..."
kubectl get helmrelease traefik -n traefik 2>/dev/null \
  && kubectl wait helmrelease/traefik -n traefik \
       --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}=True' \
       --timeout=5m \
  || warn "HelmRelease not ready yet — Flux may still be reconciling. Run: flux get helmreleases -A"

info "Done. NLB DNS:"
kubectl get service -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true
echo ""
