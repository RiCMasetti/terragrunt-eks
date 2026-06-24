data "aws_caller_identity" "current" {}

# ── EKS managed addons ───────────────────────────────────────────────────────

resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = var.cluster_name
  addon_name               = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn = aws_iam_role.vpc_cni.arn

  depends_on = [aws_iam_role_policy_attachment.vpc_cni]
}

resource "aws_eks_addon" "coredns" {
  cluster_name             = var.cluster_name
  addon_name               = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name             = var.cluster_name
  addon_name               = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  depends_on = [aws_iam_role_policy_attachment.ebs_csi]
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name             = var.cluster_name
  addon_name               = "eks-pod-identity-agent"
  resolve_conflicts_on_update = "OVERWRITE"
}

# ── IRSA: VPC CNI ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "vpc_cni" {
  name = "${var.cluster_name}-vpc-cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:aws-node"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ── IRSA: EBS CSI driver ──────────────────────────────────────────────────────

resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ── IRSA: Traefik (Route53 DNS challenge for Let's Encrypt) ───────────────────

resource "aws_iam_role" "traefik" {
  name = "${var.cluster_name}-traefik-route53"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:traefik:traefik"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "traefik_route53" {
  name = "${var.cluster_name}-traefik-route53"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ListResourceRecordSets",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/${var.route53_zone_id}"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "traefik_route53" {
  role       = aws_iam_role.traefik.name
  policy_arn = aws_iam_policy.traefik_route53.arn
}

# ── gp3 StorageClass ──────────────────────────────────────────────────────────

resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}

# ── Namespaces and Flux cluster-vars ConfigMap ─────────────────────────────────
# flux-system namespace is created here so the ConfigMap exists before flux bootstrap.
# Flux bootstrap is idempotent and won't fail if the namespace already exists.

resource "kubernetes_namespace" "flux_system" {
  metadata {
    name = "flux-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terragrunt"
    }
  }
}

resource "kubernetes_namespace" "traefik" {
  metadata {
    name = "traefik"
    labels = {
      "app.kubernetes.io/managed-by" = "flux"
    }
  }
}

resource "kubernetes_config_map" "flux_cluster_vars" {
  metadata {
    name      = "cluster-vars"
    namespace = kubernetes_namespace.flux_system.metadata[0].name
  }

  data = {
    TRAEFIK_ROLE_ARN = aws_iam_role.traefik.arn
    AWS_REGION       = var.aws_region
    DOMAIN_NAME      = var.domain_name
    ROUTE53_ZONE_ID  = var.route53_zone_id
  }
}
