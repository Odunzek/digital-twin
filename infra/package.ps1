# package.ps1
# Windows PowerShell script to package the Lambda function into a ZIP file.
#
# Run this from the twin/ project ROOT before "terraform apply":
#   .\infra\package.ps1
#
# What it does:
#   1. Moves into the backend/ directory
#   2. Installs all Python dependencies into a flat folder (backend\package\)
#   3. Copies all Python source files into the same folder
#   4. Copies the data/ directory (facts, PDF, etc.) into the same folder
#   5. ZIPs everything into infra\lambda.zip
#   6. Deletes the temporary package\ folder
#
# Why a flat folder instead of a virtual environment?
#   Lambda requires all files to be at the root of the ZIP — not nested inside
#   a site-packages/ subfolder the way virtual environments work.
#   "pip install -t <dir>" installs packages flat into a target directory.
#   "uv" does not support the -t flag, so we use plain pip here.
#
# After this script runs, terraform apply reads lambda.zip and uploads it to Lambda.
# source_code_hash in lambda.tf detects whether the ZIP has changed since last apply.

Write-Host "Packaging Lambda function..."

# Move into backend/ where requirements.txt and source .py files live
Set-Location ..\backend

# Install Linux-compatible binaries for Lambda (runs on Linux x86_64, not Windows).
# --platform manylinux2014_x86_64: fetch Linux wheels even when running on Windows
# --only-binary=:all: reject any package that would need to compile from source
# --python-version 3.12: match the Lambda runtime version
pip install -r requirements.txt -t .\package --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.12 --quiet

# Copy all .py source files into the package directory.
# This includes: server.py, lambda_handler.py, context.py, resources.py,
#                secrets.py (new), dynamo_memory.py (new)
Copy-Item *.py package\

# Copy the data directory containing your Digital Twin persona files:
#   facts.json, linkedin.pdf, style.txt, summary.txt
# These are read by resources.py when Lambda starts up.
if (Test-Path data) {
    Copy-Item -Recurse data package\data
}

# Create lambda.zip from the contents of the package\ directory.
# -Force overwrites an existing lambda.zip from a previous packaging run.
# The ZIP is placed in infra\ so Terraform can find it (filename = "lambda.zip" in lambda.tf).
Compress-Archive -Path package\* -DestinationPath ..\infra\lambda.zip -Force

# Delete the temporary package\ directory — it is no longer needed once the ZIP exists.
Remove-Item -Recurse -Force package

Write-Host "Done: infra\lambda.zip created successfully."
