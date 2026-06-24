locals {
  cluster_name       = get_env("TF_VAR_cluster_name", "eks-cluster")
  kubernetes_version = get_env("TF_VAR_kubernetes_version", "1.32")

  # Comma-separated list of EC2 instance types, e.g. "t3.medium,t3.large"
  instance_types = split(",", get_env("TF_VAR_instance_types", "t3.medium"))

  node_min_size     = tonumber(get_env("TF_VAR_node_min_size", "2"))
  node_max_size     = tonumber(get_env("TF_VAR_node_max_size", "5"))
  node_desired_size = tonumber(get_env("TF_VAR_node_desired_size", "3"))

  vpc_cidr           = get_env("TF_VAR_vpc_cidr", "10.0.0.0/16")
  single_nat_gateway = tobool(get_env("TF_VAR_single_nat_gateway", "false"))

  domain_name     = get_env("TF_VAR_domain_name")
  route53_zone_id = get_env("TF_VAR_route53_zone_id")

  github_org  = get_env("TF_VAR_github_org")
  github_repo = get_env("TF_VAR_github_repo", "terragrunt-eks")

  traefik_nodeport_http  = 30000
  traefik_nodeport_https = 30001
}
