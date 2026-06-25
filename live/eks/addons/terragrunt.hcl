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
  cluster_name      = local.c.cluster_name
  cluster_version   = local.c.kubernetes_version
  oidc_provider_arn = dependency.cluster.outputs.oidc_provider_arn
  oidc_provider_url = dependency.cluster.outputs.oidc_provider_url
  route53_zone_id   = local.c.route53_zone_id
}
