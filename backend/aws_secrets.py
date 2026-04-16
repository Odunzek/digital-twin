# secrets.py
# Retrieves configuration values from AWS Secrets Manager.
#
# Why Secrets Manager instead of environment variables?
#   - Environment variables are visible in the Lambda console in plaintext
#   - The CloudFront URL is not known until AFTER the first terraform apply,
#     so it cannot be set in terraform as an env var without a second apply
#   - Secrets Manager values can be updated (e.g., after a CloudFront URL change)
#     without redeploying Lambda
#
# The secret stored in AWS looks like a JSON string:
#   {"CORS_ORIGINS": "https://d1234abcd.cloudfront.net"}
# This module fetches that string and parses it into a Python dict.

import boto3
import json
import os

# Module-level cache: a dictionary that persists for the lifetime of the
# Lambda execution environment (between warm invocations).
# The first time get_secret() is called, it fetches from AWS and stores the result here.
# Every subsequent call in the same warm execution environment returns the cached value
# instantly — no network round-trip to Secrets Manager.
_cache = {}


def get_secret(secret_name: str) -> dict:
    """
    Retrieve a secret from AWS Secrets Manager and return it as a Python dict.

    Parameters:
        secret_name: the name of the secret in Secrets Manager
                     (e.g., "twin/config-dev" — matches SECRET_NAME env var)

    Returns:
        A dict of the secret's key-value pairs, e.g. {"CORS_ORIGINS": "https://..."}
        Returns {} (empty dict) on any error so callers can apply fallback defaults.

    How a Lambda cold start works with this function:
        1. Lambda downloads your ZIP, runs the module-level code (sets _cache = {})
        2. The first request calls get_secret() → cache miss → fetches from AWS → caches
        3. Subsequent requests (warm starts) call get_secret() → cache hit → instant return
    """
    # Check the in-memory cache first — if the secret is already here, return it immediately.
    # This is the warm-start fast path: no network call needed.
    if secret_name in _cache:
        return _cache[secret_name]

    # AWS automatically injects the AWS_REGION environment variable inside Lambda.
    # When running locally (e.g., for testing), it falls back to "us-east-1".
    region = os.getenv("AWS_REGION", "us-east-1")

    # Create a boto3 client for the "secretsmanager" service.
    # This is the same boto3.client() pattern used to create the bedrock-runtime client
    # in server.py — just a different service name.
    client = boto3.client("secretsmanager", region_name=region)

    try:
        # get_secret_value fetches the secret metadata and its value.
        # SecretId accepts the secret's name or its full ARN — we use the name.
        response = client.get_secret_value(SecretId=secret_name)

        # The secret's value is stored as a JSON-encoded string in SecretString.
        # Example: '{"CORS_ORIGINS": "https://d1234abcd.cloudfront.net"}'
        # json.loads() converts that string into a Python dict we can index with keys.
        secret_string = response["SecretString"]
        secret_dict = json.loads(secret_string)

        # Store in cache so subsequent calls in this execution environment are instant
        _cache[secret_name] = secret_dict
        return secret_dict

    except Exception as e:
        # Print to stdout so the error appears in CloudWatch Logs for debugging.
        # We return an empty dict instead of raising so the application can
        # fall back to default values (e.g., CORS_ORIGINS defaults to localhost).
        print(f"Warning: could not retrieve secret '{secret_name}': {e}")
        return {}
