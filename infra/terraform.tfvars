# terraform.tfvars
# Sets the actual values for the variables declared in variables.tf.
# Terraform loads this file automatically — no need to pass it on the command line.
#
# This file is safe to commit to Git because it contains no secrets.
# If you ever add sensitive values here (e.g., API keys), add the file to .gitignore immediately.

aws_region       = "us-east-1"        # Change this if your AWS CLI is configured for a different region
project_name     = "twin"
environment      = "dev"              # Used for resource tags only; resource names use the workspace name
bedrock_model_id = "global.amazon.nova-2-lite-v1:0"
lambda_timeout   = 30
