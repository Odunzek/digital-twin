param(
    [Parameter(Mandatory=$true)]
    [string]$Environment,
    [string]$ProjectName = "twin"
)

if ($Environment -notmatch '^(dev|test|prod)$') {
    Write-Host "Error: Invalid environment '$Environment'" -ForegroundColor Red
    Write-Host "Available environments: dev, test, prod" -ForegroundColor Yellow
    exit 1
}

Write-Host "Preparing to destroy $ProjectName-$Environment infrastructure..." -ForegroundColor Yellow

# Navigate to infra directory
Set-Location (Join-Path (Split-Path $PSScriptRoot -Parent) "infra")

$awsAccountId = aws sts get-caller-identity --query Account --output text
$awsRegion    = if ($env:DEFAULT_AWS_REGION) { $env:DEFAULT_AWS_REGION } else { "us-east-1" }

Write-Host "Initializing Terraform with S3 backend..." -ForegroundColor Yellow
terraform init -input=false `
  -backend-config="bucket=twin-terraform-state-$awsAccountId" `
  -backend-config="key=$Environment/terraform.tfstate" `
  -backend-config="region=$awsRegion" `
  -backend-config="dynamodb_table=twin-terraform-locks" `
  -backend-config="encrypt=true"

# Verify workspace exists before attempting destroy
$workspaces = terraform workspace list
if (-not ($workspaces | Select-String "^\*?\s+${Environment}\s*$")) {
    Write-Host "Error: Workspace '$Environment' does not exist" -ForegroundColor Red
    Write-Host "Available workspaces:" -ForegroundColor Yellow
    terraform workspace list
    exit 1
}

terraform workspace select $Environment

# ── Empty S3 frontend bucket ──────────────────────────────────────────────────
# Terraform cannot delete a non-empty S3 bucket, so we empty it first.
Write-Host "Emptying S3 frontend bucket..." -ForegroundColor Yellow
$FrontendBucket = "$ProjectName-$Environment-frontend-$awsAccountId"

try {
    aws s3 ls "s3://$FrontendBucket" 2>$null | Out-Null
    Write-Host "  Emptying $FrontendBucket..." -ForegroundColor Gray
    aws s3 rm "s3://$FrontendBucket" --recursive
} catch {
    Write-Host "  Frontend bucket not found or already empty" -ForegroundColor Gray
}

# ── Terraform destroy ─────────────────────────────────────────────────────────
Write-Host "Running terraform destroy..." -ForegroundColor Yellow
terraform destroy `
  -var="project_name=$ProjectName" `
  -var="environment=$Environment" `
  -var="aws_region=$awsRegion" `
  -auto-approve

Write-Host ""
Write-Host "Infrastructure for $Environment has been destroyed!" -ForegroundColor Green
Write-Host ""
Write-Host "To remove the workspace completely, run:" -ForegroundColor Cyan
Write-Host "  cd infra" -ForegroundColor White
Write-Host "  terraform workspace select default" -ForegroundColor White
Write-Host "  terraform workspace delete $Environment" -ForegroundColor White
