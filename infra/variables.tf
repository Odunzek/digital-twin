# variables.tf
# Declares all input variables used across the Terraform configuration.
# Think of variables like function parameters — they let the same .tf files work
# in different contexts (different regions, project names, environments).
#
# Variable values are set in terraform.tfvars (loaded automatically).
# The "default" field provides a fallback if a value is not supplied.

variable "aws_region" {
  description = "AWS region where all resources will be created (e.g., us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as a prefix for all resource names (e.g., 'twin'). Keep it short and lowercase."
  type        = string
  default     = "essay-coach"
}

variable "environment" {
  description = "Environment label used in resource tags only. Resource names use the Terraform workspace name instead."
  type        = string
  default     = "dev"
}

# The Bedrock model to use for AI responses.
# The "global." prefix tells Bedrock to route to the best available region,
# giving higher effective throughput and fewer throttling errors than a region-specific ID.
variable "bedrock_model_id" {
  description = "Bedrock model ID. Use the global. cross-region inference prefix for best availability."
  type        = string
  default     = "global.amazon.nova-2-lite-v1:0"
}

# Lambda will abort a request that takes longer than this many seconds.
# Bedrock calls typically complete in 2–10 seconds, so 30s provides a safe buffer.
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds. Must be long enough for a Bedrock response."
  type        = number
  default     = 30
}
