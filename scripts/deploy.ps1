param(
    [string]$Environment = "dev",
    [string]$ProjectName = "twin"
)
$ErrorActionPreference = "Stop"

Write-Host "Deploying $ProjectName to $Environment..." -ForegroundColor Green

# Navigate to project root
Set-Location (Split-Path $PSScriptRoot -Parent)

# ── 1. Build Lambda package ───────────────────────────────────────────────────
Write-Host "Building Lambda package..." -ForegroundColor Yellow
Set-Location backend

# Clean any previous package directory
if (Test-Path package) { Remove-Item -Recurse -Force package }

# Install Python dependencies as flat files (Lambda requires flat layout, not venv).
# --platform manylinux2014_x86_64 fetches Linux wheels even when run on Windows.
# --only-binary=:all:              refuse any package that would compile from source.
# --python-version 3.12            match the Lambda runtime.
pip install -r requirements.txt -t .\package `
  --platform manylinux2014_x86_64 `
  --only-binary=:all: `
  --python-version 3.12 `
  --quiet

# Copy Python source files and persona data into the package directory
Copy-Item *.py package\
if (Test-Path data) { Copy-Item -Recurse data package\data }

# Zip everything into infra\lambda.zip (Terraform reads it from there)
Compress-Archive -Path package\* -DestinationPath ..\infra\lambda.zip -Force
Remove-Item -Recurse -Force package
Set-Location ..

Write-Host "Lambda package ready: infra\lambda.zip" -ForegroundColor Yellow

# ── 2. Terraform init, workspace, apply ──────────────────────────────────────
Set-Location infra

$awsAccountId = aws sts get-caller-identity --query Account --output text
$awsRegion    = if ($env:DEFAULT_AWS_REGION) { $env:DEFAULT_AWS_REGION } else { "us-east-1" }

Write-Host "Initializing Terraform with S3 backend..." -ForegroundColor Yellow
terraform init -input=false `
  -backend-config="bucket=twin-terraform-state-$awsAccountId" `
  -backend-config="key=$Environment/terraform.tfstate" `
  -backend-config="region=$awsRegion" `
  -backend-config="dynamodb_table=twin-terraform-locks" `
  -backend-config="encrypt=true"

# Create workspace if it doesn't exist, otherwise select it
$workspaces = terraform workspace list
if (-not ($workspaces | Select-String "^\*?\s+${Environment}\s*$")) {
    Write-Host "Creating workspace: $Environment" -ForegroundColor Yellow
    terraform workspace new $Environment
} else {
    terraform workspace select $Environment
}

Write-Host "Applying Terraform..." -ForegroundColor Yellow
terraform apply `
  -var="project_name=$ProjectName" `
  -var="environment=$Environment" `
  -var="aws_region=$awsRegion" `
  -auto-approve

# Capture outputs
$ApiUrl           = terraform output -raw api_gateway_url
$CloudfrontDomain = terraform output -raw cloudfront_domain
$FrontendBucket   = terraform output -raw frontend_bucket_name

Set-Location ..

# ── 3. Build and deploy frontend ─────────────────────────────────────────────
Write-Host "Building frontend..." -ForegroundColor Yellow
Set-Location frontend

# Write the API URL so Next.js bakes it into the static build
"NEXT_PUBLIC_API_URL=$ApiUrl" | Out-File .env.production -Encoding utf8

npm install
npm run build

Write-Host "Uploading frontend to S3..." -ForegroundColor Yellow
aws s3 sync .\out "s3://$FrontendBucket/" --delete

Set-Location ..

# ── 4. Summary ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host "CloudFront URL : https://$CloudfrontDomain" -ForegroundColor Cyan
Write-Host "API Gateway    : $ApiUrl" -ForegroundColor Cyan
Write-Host "Frontend Bucket: $FrontendBucket" -ForegroundColor Cyan
