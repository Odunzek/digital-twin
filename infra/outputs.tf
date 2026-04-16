# outputs.tf
# Declares values that Terraform prints after a successful "terraform apply".
# Outputs let you capture important resource attributes (URLs, names, ARNs)
# without having to dig through the AWS console.
#
# After apply you will see something like:
#   api_gateway_url      = "https://abc123.execute-api.us-east-1.amazonaws.com"
#   cloudfront_domain    = "d1234abcd.cloudfront.net"
#   dynamodb_table_name  = "twin-dev-conversations"
#   ...

# The full HTTPS URL for the API Gateway invoke endpoint.
# Use this in frontend/components/twin.tsx as the API base URL.
# Example: "https://abc123.execute-api.us-east-1.amazonaws.com"
output "api_gateway_url" {
  description = "API Gateway invoke URL — paste this into twin.tsx as the backend API URL"
  value       = aws_apigatewayv2_api.twin.api_endpoint
}

# The CloudFront domain name (without https://).
# Use this in Step 6.4 to update the Secrets Manager secret with the correct CORS origin.
# Example: "d1234abcd.cloudfront.net"
output "cloudfront_domain" {
  description = "CloudFront domain name — used to build the CORS origin URL and access the frontend"
  value       = aws_cloudfront_distribution.twin.domain_name
}

# The DynamoDB table name where conversations are stored.
# Useful for inspecting data in the AWS console (Part 7) and confirming the correct table.
output "dynamodb_table_name" {
  description = "DynamoDB table name for conversation memory"
  value       = aws_dynamodb_table.conversations.name
}

# The S3 bucket name where the compiled frontend files will be uploaded.
# Used in Step 6.5 when running "aws s3 sync frontend/out/ s3://BUCKET_NAME/ --delete"
output "frontend_bucket_name" {
  description = "S3 bucket name for the static frontend — upload the Next.js build output here"
  value       = aws_s3_bucket.frontend.bucket
}

# The Lambda function name.
# Useful if you need to manually update code without a full terraform apply
# (e.g., using "aws lambda update-function-code --function-name NAME --zip-file ...")
output "lambda_function_name" {
  description = "Lambda function name — use this to redeploy code manually if needed"
  value       = aws_lambda_function.twin_api.function_name
}

# The Secrets Manager secret name.
# Used in Step 6.4 to update the CORS_ORIGINS value with the real CloudFront URL.
output "secret_name" {
  description = "Secrets Manager secret name — update this with your CloudFront URL after first apply"
  value       = aws_secretsmanager_secret.twin_config.name
}
