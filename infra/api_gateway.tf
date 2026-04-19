# api_gateway.tf
# Defines the HTTP API Gateway that acts as the front door for your Lambda backend.
#
# Request flow:
#   Browser → CloudFront → API Gateway → Lambda (FastAPI) → Bedrock / DynamoDB
#
# API Gateway handles:
#   - Receiving HTTP requests from the browser
#   - Forwarding them to Lambda in the correct format
#   - Enforcing CORS (Cross-Origin Resource Sharing) rules
#   - Returning Lambda's response back to the browser

# ─── HTTP API ─────────────────────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "twin" {
  name          = "${local.name_prefix}-api-gateway"  # e.g., "twin-dev-api-gateway"
  protocol_type = "HTTP"

  # CORS configuration tells browsers which origins are allowed to call this API.
  # CORS is enforced by browsers: a script from origin A cannot call API at origin B
  # unless B explicitly permits it via CORS headers.
  #
  # Key point: we reference aws_cloudfront_distribution.twin.domain_name directly.
  # Terraform builds a dependency graph from these references and automatically
  # creates CloudFront BEFORE this API Gateway, so the domain name is known here.
  # This eliminates the manual two-step CORS update that was needed in Activity 03
  # (where you had to deploy, note the CloudFront URL, then go back and update Lambda).
  cors_configuration {
    allow_headers = ["*"]                          # Allow any request header
    allow_methods = ["GET", "POST", "OPTIONS"]     # OPTIONS is required for CORS preflight
    allow_origins = ["https://${aws_cloudfront_distribution.twin.domain_name}"]
    max_age       = 300  # Browser caches the CORS preflight response for 5 minutes (300 seconds)
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# Stage: a named slot for an API deployment.
# "$default" is a special stage that receives all requests without a path prefix.
# auto_deploy = true means every configuration change takes effect immediately,
# without needing a manual "Deploy API" step in the console.
resource "aws_apigatewayv2_stage" "twin_default" {
  api_id      = aws_apigatewayv2_api.twin.id
  name        = "$default"
  auto_deploy = true
}

# Integration: the connection between API Gateway and Lambda.
# AWS_PROXY means API Gateway forwards the full, unmodified HTTP request to Lambda
# and returns Lambda's full response to the caller — no transformation applied.
# payload_format_version "2.0" is the modern event format that Mangum (in lambda_handler.py)
# knows how to translate into a FastAPI-compatible ASGI request.
resource "aws_apigatewayv2_integration" "twin_lambda" {
  api_id                 = aws_apigatewayv2_api.twin.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.twin_api.invoke_arn  # Lambda's invocation ARN
  payload_format_version = "2.0"
}

# Route: POST /chat — the main conversation endpoint.
# When the browser sends POST /chat, API Gateway routes it to the Lambda integration.
# The "target" links this route to the integration defined above.
# "integrations/" prefix is required by the API Gateway resource syntax.
resource "aws_apigatewayv2_route" "api_route" {
  api_id    = aws_apigatewayv2_api.twin.id
  route_key = "POST /api"
  target    = "integrations/${aws_apigatewayv2_integration.twin_lambda.id}"
}

# Route: GET /health — used to verify the backend is alive.
# The frontend or monitoring tools can call /health to check the deployment.
# Same Lambda integration — all routes go through the same FastAPI app.
resource "aws_apigatewayv2_route" "health_route" {
  api_id    = aws_apigatewayv2_api.twin.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.twin_lambda.id}"
}

# Permission: explicitly grants API Gateway the right to invoke the Lambda function.
# Even though we configured the integration above, IAM still blocks the invocation
# unless this resource_based policy is present. Think of it as a door key:
# the integration says "go through this door", but this permission provides the key.
#
# source_arn uses "/*/*" at the end, which means:
#   "any method (GET, POST, etc.) on any stage of this specific API is allowed"
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.twin_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.twin.execution_arn}/*/*"
}
