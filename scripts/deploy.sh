#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
PROJECT_NAME=${2:-essay-coach}

echo "Deploying ${PROJECT_NAME} to ${ENVIRONMENT}..."

# Navigate to project root
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

# ── 1. Build Lambda package ───────────────────────────────────────────────────
echo "Building Lambda package..."

rm -rf package

pip install -r requirements.txt -t ./package \
  --platform manylinux2014_x86_64 \
  --only-binary=:all: \
  --python-version 3.12 \
  --quiet

cp server.py lambda_handler.py app_secrets.py dynamo_memory.py package/

cd package
zip -r "${PROJECT_ROOT}/infra/lambda.zip" . --quiet
cd "${PROJECT_ROOT}"
rm -rf package

echo "Lambda package ready: infra/lambda.zip"

# ── 2. Terraform init, workspace, apply ──────────────────────────────────────
cd infra

AWS_REGION=${DEFAULT_AWS_REGION:-us-east-1}

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Initializing Terraform..."
terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="encrypt=true"

# Create workspace if it doesn't exist, otherwise select it
if ! terraform workspace list | grep -q "^[* ]*${ENVIRONMENT}$"; then
  echo "Creating workspace: ${ENVIRONMENT}"
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

echo "Applying Terraform..."
terraform apply \
  -var="project_name=${PROJECT_NAME}" \
  -var="environment=${ENVIRONMENT}" \
  -var="aws_region=${AWS_REGION}" \
  -auto-approve

# Capture outputs
API_URL=$(terraform output -raw api_gateway_url)
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain)
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name)

cd "${PROJECT_ROOT}"

# ── 3. Build and deploy frontend ─────────────────────────────────────────────
echo "Building frontend..."

cat > .env.production <<EOF
NEXT_PUBLIC_API_URL=${API_URL}
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=${NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY}
EOF

npm install
NEXT_EXPORT=true npm run build

echo "Uploading frontend to S3..."
aws s3 sync ./out "s3://${FRONTEND_BUCKET}/" --delete

# ── 4. Update Secrets Manager with real CloudFront URL ────────────────────────
SECRET_NAME="${PROJECT_NAME}/config-${ENVIRONMENT}"
echo "Updating Secrets Manager: ${SECRET_NAME}..."
aws secretsmanager update-secret \
  --secret-id "${SECRET_NAME}" \
  --secret-string "{\"CORS_ORIGINS\": \"https://${CLOUDFRONT_DOMAIN}\"}" \
  --region "${AWS_REGION}" > /dev/null 2>&1 || echo "Secrets Manager update skipped (secret may not exist yet)"

# ── 5. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "Deployment complete!"
echo "CloudFront URL : https://${CLOUDFRONT_DOMAIN}"
echo "API Gateway    : ${API_URL}"
echo "Frontend Bucket: ${FRONTEND_BUCKET}"
