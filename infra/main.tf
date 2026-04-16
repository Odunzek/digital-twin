# main.tf
# This is the entry point for the entire Terraform configuration.
# It tells Terraform which version of itself to use and which cloud provider to connect to.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      # source: where to download the AWS provider plugin from (Terraform registry)
      source  = "hashicorp/aws"
      # ~> 5.0 means "any 5.x version" — allows minor updates but not a breaking major version
      version = "~> 5.0"
    }
  }
}

# The AWS provider authenticates to your AWS account and sets the default region.
# var.aws_region is defined in variables.tf and given a value in terraform.tfvars.
provider "aws" {
  region = var.aws_region
}

# Data sources READ existing information from AWS without creating or changing anything.
# data.aws_caller_identity.current.account_id → your 12-digit AWS account number
# data.aws_region.current.name                → the active region (e.g., "us-east-1")
# These are used in other files to build resource ARNs without hardcoding account info.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# locals are named expressions computed once and reused across ALL .tf files in this directory.
# By combining the project name and workspace name here, every resource in every file
# automatically gets a unique, environment-specific name.
#
# Example (in the "dev" workspace):
#   name_prefix  = "twin-dev"
#   s3_origin_id = "twin-s3-origin-dev"
#
# Example (in the "prod" workspace):
#   name_prefix  = "twin-prod"
#   s3_origin_id = "twin-s3-origin-prod"
locals {
  name_prefix  = "${var.project_name}-${terraform.workspace}"
  s3_origin_id = "${var.project_name}-s3-origin-${terraform.workspace}"
}
