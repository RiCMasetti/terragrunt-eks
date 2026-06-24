module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_endpoint_public_access = true

  # Addons are managed separately in the eks-addons module
  cluster_addons = {}

  eks_managed_node_groups = {
    main = {
      name           = "${var.cluster_name}-ng"
      instance_types = var.instance_types

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      subnet_ids = var.private_subnet_ids

      labels = {
        role = "general"
      }

      # Enable SSM for node access without bastion
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  # Required for IRSA (used by EBS CSI driver, Traefik, etc.)
  enable_irsa = true
}
