locals {
  aws_account_id = get_env("AWS_ACCOUNT_ID")
  aws_region     = get_env("AWS_DEFAULT_REGION", "us-east-1")
}

generate "provider" {
  path      = "_generated_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  default_tags {
    tags = {
      ManagedBy  = "terragrunt"
      Repository = "terragrunt-eks"
    }
  }
}
EOF
}

remote_state {
  backend = "s3"
  generate = {
    path      = "_generated_backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "tfstate-${local.aws_account_id}-${local.aws_region}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = "tfstate-locks"
  }
}
