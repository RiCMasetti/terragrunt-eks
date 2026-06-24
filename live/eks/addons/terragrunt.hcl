include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  c = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
}

terraform {
  source = "../../../modules/eks-addons"
}

dependency "cluster" {
  config_path = "../cluster"
}

inputs = {
  cluster_name      = local.c.cluster_name
  cluster_version   = local.c.kubernetes_version
  oidc_provider_arn = dependency.cluster.outputs.oidc_provider_arn
  oidc_provider_url = dependency.cluster.outputs.oidc_provider_url
  aws_region        = get_env("AWS_DEFAULT_REGION", "us-east-1")
  domain_name       = local.c.domain_name
  route53_zone_id   = local.c.route53_zone_id
}
