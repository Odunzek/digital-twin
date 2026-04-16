#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
PROJECT_NAME=${2:-twin}

echo "Deploying ${PROJECT_NAME} to ${ENVIRONMENT}..."

# Navigate to project root (works whether called from any directory)
cd "$(dirname "$0")/.."

# ── 1. Build Lambda package ───────────────────────────────────────────────────
echo "Building Lambda package..."
cd backend

# Clean any previous package directory
rm -rf package

# Install Python dependencies as flat files (Lambda requires flat layout, not venv).
# --platform manylinux2014_x86_64 fetches Linux wheels even when run on macOS.
# --only-binary=:all:              refuse any package that would compile from source.
# --python-version 3.12            match the Lambda runtime.
pip install -r requirements.txt -t ./package \
  --platform manylinux2014_x86_64 \
  --only-binary=:all: \
  --python-version 3.12 \
  --quiet

# Copy Python source files into the package directory
cp *.py package/

# Copy persona data files if they exist
if [ -d data ]; then
  cp -r data package/data
fi

# Zip everything into infra/lambda.zip (Terraform reads it from there)
cd package
zip -r ../../infra/lambda.zip . --quiet
cd ..
rm -rf package
cd ..

echo "Lambda package ready: infra/lambda.zip"

# ── 2. Terraform init, workspace, apply ──────────────────────────────────────
cd infra

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${DEFAULT_AWS_REGION:-us-east-1}

echo "Initializing Terraform with S3 backend..."
terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
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

cd ..

# ── 3. Build and deploy frontend ─────────────────────────────────────────────
echo "Building frontend..."
cd frontend

# Write the API URL so Next.js bakes it into the static build
echo "NEXT_PUBLIC_API_URL=${API_URL}" > .env.production

npm install
npm run build

echo "Uploading frontend to S3..."
aws s3 sync ./out "s3://${FRONTEND_BUCKET}/" --delete

cd ..

# ── 4. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "Deployment complete!"
echo "CloudFront URL : https://${CLOUDFRONT_DOMAIN}"
echo "API Gateway    : ${API_URL}"
echo "Frontend Bucket: ${FRONTEND_BUCKET}"
