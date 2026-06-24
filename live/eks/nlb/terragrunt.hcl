include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  c = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
}

terraform {
  source = "../../../modules/nlb"
}

dependency "vpc" {
  config_path = "../vpc"
}

dependency "cluster" {
  config_path = "../cluster"
}

inputs = {
  cluster_name           = local.c.cluster_name
  vpc_id                 = dependency.vpc.outputs.vpc_id
  public_subnet_ids      = dependency.vpc.outputs.public_subnet_ids
  vpc_cidr_block         = dependency.vpc.outputs.vpc_cidr_block
  node_security_group_id = dependency.cluster.outputs.node_security_group_id
  traefik_nodeport_http  = local.c.traefik_nodeport_http
  traefik_nodeport_https = local.c.traefik_nodeport_https
}
