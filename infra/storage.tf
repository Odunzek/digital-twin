# storage.tf
# Defines three storage resources:
#
#   1. DynamoDB table  — stores conversation history per session (replaces S3 JSON from Activity 03)
#   2. S3 bucket       — hosts the compiled Next.js frontend (HTML, CSS, JS)
#   3. Secrets Manager — stores the CloudFront URL so Lambda can configure CORS at runtime
#
# Why DynamoDB instead of S3 for conversations?
#   - DynamoDB is a key-value database: one get_item call returns a session's full history
#   - S3 requires an HTTP GET request per file, which is slower and costs more per operation
#   - DynamoDB has built-in TTL: items expire automatically — no cleanup job needed
#   - DynamoDB scales to any load without any configuration changes

# ─── DynamoDB Table ───────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "conversations" {
  name         = "${local.name_prefix}-conversations"  # e.g., "twin-dev-conversations"

  # PAY_PER_REQUEST: you pay only for actual reads/writes — no upfront capacity planning.
  # This is ideal for unpredictable or low-volume workloads like a student project.
  billing_mode = "PAY_PER_REQUEST"

  # hash_key is the primary key — every item must have a unique session_id.
  # DynamoDB uses this to know which "row" to read or write.
  hash_key     = "session_id"

  # You only declare attributes that are used as keys (hash_key or sort_key).
  # The "messages", "updated_at", and "ttl" fields don't appear here because
  # DynamoDB is schemaless for non-key attributes — you can store anything.
  attribute {
    name = "session_id"
    type = "S"  # S = String (other options: N = Number, B = Binary)
  }

  # TTL (Time to Live): DynamoDB reads the "ttl" attribute on each item.
  # When that Unix timestamp has passed, DynamoDB automatically deletes the item.
  # dynamo_memory.py sets ttl = now + 30 days when saving a conversation.
  # This keeps the table from growing forever without any scheduled cleanup code.
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# ─── S3 Bucket for Static Frontend ───────────────────────────────────────────
# This bucket holds the output of "npm run build" (the frontend/out/ directory).
# CloudFront sits in front of it and serves these files over HTTPS worldwide.

resource "aws_s3_bucket" "frontend" {
  # S3 bucket names must be globally unique across ALL AWS accounts worldwide.
  # Appending the account ID guarantees uniqueness — no one else has your account ID.
  bucket = "${local.name_prefix}-frontend-${data.aws_caller_identity.current.account_id}"

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# Enable S3 static website hosting mode.
# In this mode, S3 serves index.html automatically for the root URL,
# and redirects unknown paths to index.html (needed for Next.js client-side routing).
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document { suffix = "index.html" }
  error_document { key    = "index.html" }
}

# By default, S3 blocks all public access as a security precaution.
# We must explicitly disable these blocks because CloudFront fetches files
# from the S3 website endpoint using public URLs (not presigned URLs or IAM).
# This is safe here because the bucket only holds public frontend assets — no secrets.
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Bucket policy: grants read access to everyone (Principal = "*").
# Action s3:GetObject allows anyone to download files from this bucket.
# The Resource ends with "/*" meaning the policy applies to every file inside the bucket.
resource "aws_s3_bucket_policy" "frontend_public_read" {
  bucket = aws_s3_bucket.frontend.id

  # depends_on ensures the public access block is removed BEFORE the policy is applied.
  # If the block is still active when the policy is created, AWS would reject the
  # policy with an "Access Denied" error because it allows public access.
  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"                              # Anyone on the internet
      Action    = "s3:GetObject"                  # Can download files
      Resource  = "${aws_s3_bucket.frontend.arn}/*"  # From any file in this bucket
    }]
  })
}

# ─── AWS Secrets Manager Secret ───────────────────────────────────────────────
# Stores the CloudFront URL so Lambda can configure CORS correctly at runtime.
#
# Why Secrets Manager instead of a Lambda environment variable?
#   - After the first terraform apply, you don't know the CloudFront URL yet.
#   - If CORS_ORIGINS were an env var, you'd need to re-run terraform apply every
#     time the CloudFront URL changes, forcing a Lambda redeploy.
#   - With Secrets Manager, you update the secret once (Step 6.4) and Lambda
#     picks up the new value at the next cold start — no redeploy needed.

resource "aws_secretsmanager_secret" "twin_config" {
  name        = "${var.project_name}/config-${terraform.workspace}"  # e.g., "twin/config-dev"
  description = "Runtime configuration for the Digital Twin (${terraform.workspace} environment)"

  # recovery_window_in_days = 0 allows the secret to be deleted immediately.
  # AWS normally enforces a 7–30 day recovery window before a secret is truly gone
  # (to protect against accidental deletion in production).
  # We disable it here so "terraform destroy" works cleanly during development.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "twin_config" {
  secret_id = aws_secretsmanager_secret.twin_config.id

  # Placeholder value written on first creation.
  # You will overwrite this with your real CloudFront URL in Step 6.4:
  #   aws secretsmanager update-secret --secret-id "twin/config-dev" \
  #     --secret-string '{"CORS_ORIGINS": "https://YOUR_CLOUDFRONT_DOMAIN.cloudfront.net"}'
  secret_string = jsonencode({
    CORS_ORIGINS = "REPLACE_WITH_CLOUDFRONT_URL_AFTER_APPLY"
  })

  lifecycle {
    # CRITICAL: Without ignore_changes, every "terraform apply" would overwrite the
    # secret back to the placeholder above — wiping out the real CloudFront URL
    # you set manually after the first deploy.
    # ignore_changes = [secret_string] means: "create this field once, then never touch it again.
    # Any changes to secret_string made outside of Terraform are intentional and should be kept."
    ignore_changes = [secret_string]
  }
}
