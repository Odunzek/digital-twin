terraform {
  backend "s3" {
    # Values are passed via -backend-config flags in the deploy/destroy scripts.
    # For local use, run terraform init with the flags from scripts/deploy.ps1.
  }
}
