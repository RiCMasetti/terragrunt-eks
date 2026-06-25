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

dependency "cluster" {
  config_path = "../cluster"

  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"

  mock_outputs = {
    cluster_name           = "mock-cluster"
    cluster_endpoint       = "https://mock.eks.amazonaws.com"
    cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUN5RENDQWJDZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJeU1EVXhNREUwTURNeU5Gb1hEVE15TURVd056RTBNREl5TkZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBSzZxCkVrZVRqYU44d0FBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBCkFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUEKQUFBQUFBQT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo="
    node_security_group_id = "sg-00000000000000000"
    oidc_provider_arn      = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/AAAABBBBCCCCDDDD"
    oidc_provider_url      = "oidc.eks.eu-central-1.amazonaws.com/id/AAAABBBBCCCCDDDD"
    cluster_iam_role_arn   = "arn:aws:iam::123456789012:role/mock-cluster-role"
    cluster_version        = "1.32"
  }
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
