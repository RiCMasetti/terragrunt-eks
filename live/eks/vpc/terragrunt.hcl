include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  c = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
}

terraform {
  source = "../../../modules/vpc"
}

inputs = {
  cluster_name       = local.c.cluster_name
  vpc_cidr           = local.c.vpc_cidr
  single_nat_gateway = local.c.single_nat_gateway
}
