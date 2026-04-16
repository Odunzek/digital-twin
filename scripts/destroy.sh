#!/bin/bash
set -e

if [ $# -eq 0 ]; then
    echo "Error: Environment parameter is required"
    echo "Usage: $0 <environment>"
    echo "Example: $0 dev"
    echo "Available environments: dev, test, prod"
    exit 1
fi

ENVIRONMENT=$1
PROJECT_NAME=${2:-twin}

echo "Preparing to destroy ${PROJECT_NAME}-${ENVIRONMENT} infrastructure..."

# Navigate to infra directory
cd "$(dirname "$0")/../infra"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${DEFAULT_AWS_REGION:-us-east-1}

echo "Initializing Terraform with S3 backend..."
terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
  -backend-config="encrypt=true"

# Verify workspace exists before attempting destroy
if ! terraform workspace list | grep -q "^[* ]*${ENVIRONMENT}$"; then
    echo "Error: Workspace '${ENVIRONMENT}' does not exist"
    echo "Available workspaces:"
    terraform workspace list
    exit 1
fi

terraform workspace select "$ENVIRONMENT"

# ── Empty S3 frontend bucket ──────────────────────────────────────────────────
# Terraform cannot delete a non-empty S3 bucket, so we empty it first.
echo "Emptying S3 frontend bucket..."
FRONTEND_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-frontend-${AWS_ACCOUNT_ID}"

if aws s3 ls "s3://$FRONTEND_BUCKET" 2>/dev/null; then
    echo "  Emptying $FRONTEND_BUCKET..."
    aws s3 rm "s3://$FRONTEND_BUCKET" --recursive
else
    echo "  Frontend bucket not found or already empty"
fi

# ── Ensure lambda.zip exists ──────────────────────────────────────────────────
# Terraform reads lambda.zip during plan/apply/destroy to compute source_code_hash.
# If the zip doesn't exist (e.g. in a fresh GitHub Actions runner), create a dummy.
if [ ! -f "lambda.zip" ]; then
    echo "Creating dummy lambda.zip for destroy operation..."
    echo "dummy" | zip lambda.zip -
fi

# ── Terraform destroy ─────────────────────────────────────────────────────────
echo "Running terraform destroy..."
terraform destroy \
  -var="project_name=${PROJECT_NAME}" \
  -var="environment=${ENVIRONMENT}" \
  -var="aws_region=${AWS_REGION}" \
  -auto-approve

echo ""
echo "Infrastructure for ${ENVIRONMENT} has been destroyed!"
echo ""
echo "To remove the workspace completely, run:"
echo "  cd infra"
echo "  terraform workspace select default"
echo "  terraform workspace delete ${ENVIRONMENT}"
