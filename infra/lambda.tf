# lambda.tf
# Defines the Lambda function that runs your FastAPI backend,
# and all the IAM permissions it needs to call AWS services.
#
# IAM (Identity and Access Management) controls what each AWS resource is allowed to do.
# Lambda needs explicit permission to write logs, read/write DynamoDB, call Bedrock,
# and read from Secrets Manager. Without these, Lambda would be silently blocked.

# ─── IAM Role ────────────────────────────────────────────────────────────────
# Every Lambda function must have an "execution role" — an IAM identity that
# Lambda assumes when it runs. Think of it as Lambda's employee ID badge:
# it defines which doors (AWS services) Lambda is allowed to open.

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-role"  # e.g., "twin-dev-lambda-role"

  # The assume_role_policy is a "trust policy" — it says which AWS service
  # is allowed to assume (use) this role. Here we say: only Lambda may use it.
  # Without this, no service could assume the role and it would be useless.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# ─── Managed Policy Attachments ──────────────────────────────────────────────
# AWS provides pre-built "managed policies" — curated permission sets for common use cases.
# We attach three to the Lambda role. Each attachment is a separate resource
# so Terraform can track and manage them independently.

# 1. Basic execution: grants Lambda permission to write logs to CloudWatch.
#    Without this, every print() statement and error message would be silently lost.
#    This is the bare minimum every Lambda function needs.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 2. DynamoDB full access: allows Lambda to read and write conversation history.
#    The load_conversation() and save_conversation() functions in dynamo_memory.py
#    need GetItem and PutItem permissions at minimum. FullAccess is used here for
#    simplicity in a student project; production roles would use least-privilege.
resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# 3. Bedrock full access: allows Lambda to invoke AI models.
#    server.py calls bedrock_client.converse() — this permission makes that possible.
resource "aws_iam_role_policy_attachment" "lambda_bedrock" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}

# ─── Custom Inline Policy: Secrets Manager ───────────────────────────────────
# There is no AWS managed policy for "read a specific secret", so we write our own.
# This is an inline policy — it lives directly on the role rather than as a
# separate reusable policy. It's appropriate here because it's role-specific.
#
# The Resource ARN is scoped to secrets that start with "${var.project_name}/"
# (e.g., "twin/*"). Lambda can only read secrets that belong to this project —
# it cannot accidentally read secrets from other applications in the same account.

resource "aws_iam_role_policy" "lambda_secrets" {
  name = "${local.name_prefix}-secrets-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      # data.aws_caller_identity.current.account_id is fetched automatically from AWS —
      # no need to hardcode your 12-digit account number here.
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/*"
    }]
  })
}

# ─── Lambda Function ──────────────────────────────────────────────────────────

resource "aws_lambda_function" "twin_api" {
  # filename: the path to the deployment ZIP, relative to the infra/ directory.
  # This ZIP is created by running infra/package.ps1 before terraform apply.
  filename         = "lambda.zip"

  # source_code_hash: Terraform computes a fingerprint (SHA256 hash) of lambda.zip
  # and stores it in the state file. On the next terraform apply, if the hash has
  # changed (you updated your Python code and re-ran package.ps1), Terraform will
  # upload the new ZIP and redeploy the function. Without this line, Terraform
  # would see no changes to the resource definition and skip the redeploy —
  # your code updates would never reach Lambda.
  source_code_hash = filebase64sha256("lambda.zip")

  function_name = "${local.name_prefix}-api"     # e.g., "twin-dev-api"
  role          = aws_iam_role.lambda_exec.arn   # The IAM role defined above
  handler       = "lambda_handler.handler"        # File: lambda_handler.py, function: handler
  runtime       = "python3.12"
  timeout       = var.lambda_timeout             # From variables.tf, default 30 seconds
  memory_size   = 512                            # MB — generous for FastAPI + Bedrock

  # Environment variables are injected into the Lambda runtime and accessible
  # via os.getenv() in your Python code.
  environment {
    variables = {
      # Which Terraform workspace is active ("dev" or "prod") — useful in logs
      ENVIRONMENT      = terraform.workspace

      # Tells server.py to use DynamoDB instead of local file storage
      USE_DYNAMODB     = "true"

      # The DynamoDB table name — set to the table defined in storage.tf
      # Terraform resolves this reference automatically (cross-resource dependency)
      DYNAMODB_TABLE   = aws_dynamodb_table.conversations.name

      BEDROCK_REGION   = var.aws_region
      BEDROCK_MODEL_ID = var.bedrock_model_id

      # The Secrets Manager secret name Lambda will read at startup.
      # secrets.py calls get_secret(os.getenv("SECRET_NAME")) to retrieve
      # CORS_ORIGINS, avoiding the need to hardcode the CloudFront URL here.
      SECRET_NAME      = "${var.project_name}/config-${terraform.workspace}"

      # NOTE: CORS_ORIGINS is intentionally NOT set here.
      # It lives in Secrets Manager and is fetched at runtime by secrets.py.
      # This way, if the CloudFront URL changes, you update the secret once
      # instead of modifying the Lambda environment and redeploying.

      CLERK_JWKS_URL   = "https://ultimate-rabbit-96.clerk.accounts.dev/.well-known/jwks.json"
    }
  }

  # depends_on ensures all three policy attachments are complete BEFORE Lambda is created.
  # IAM changes can take a few seconds to propagate. Without this, Lambda might
  # start up before it has the DynamoDB or Bedrock permissions it needs.
  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_iam_role_policy_attachment.lambda_dynamodb,
    aws_iam_role_policy_attachment.lambda_bedrock,
  ]

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}
