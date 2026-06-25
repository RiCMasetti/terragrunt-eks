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

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"

  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002", "subnet-00000000000000003"]
    public_subnet_ids  = ["subnet-00000000000000004", "subnet-00000000000000005", "subnet-00000000000000006"]
    vpc_cidr_block     = "10.0.0.0/16"
    azs                = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  }
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
