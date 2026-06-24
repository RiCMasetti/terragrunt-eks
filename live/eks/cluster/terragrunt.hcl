include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  c = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
}

terraform {
  source = "../../../modules/eks"
}

dependency "vpc" {
  config_path = "../vpc"
}

inputs = {
  cluster_name       = local.c.cluster_name
  kubernetes_version = local.c.kubernetes_version
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids
  instance_types     = local.c.instance_types
  node_min_size      = local.c.node_min_size
  node_max_size      = local.c.node_max_size
  node_desired_size  = local.c.node_desired_size
}
