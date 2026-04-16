# server.py
# The FastAPI application that powers the Digital Twin backend.
#
# Changes from Activity 03:
#   - Conversation memory now uses DynamoDB (via dynamo_memory.py) instead of S3 JSON files
#   - CORS origins are now loaded from AWS Secrets Manager (via secrets.py) instead of
#     a hardcoded Lambda environment variable
#   - The health endpoint now reports "storage: dynamodb" when deployed
#
# Local development (USE_DYNAMODB=false):
#   - No DynamoDB or Secrets Manager calls are made
#   - CORS origins are read from the CORS_ORIGINS environment variable (or .env file)
#   - Conversation is not persisted between requests (stateless for local testing)
#
# Production / Lambda (USE_DYNAMODB=true):
#   - CORS origins are fetched from Secrets Manager at startup
#   - Conversations are loaded from and saved to DynamoDB per request

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
from dotenv import load_dotenv
from typing import Optional, List, Dict
import uuid
from datetime import datetime
import boto3
from botocore.exceptions import ClientError
from context import prompt

# Import DynamoDB memory functions (defined in dynamo_memory.py)
from dynamo_memory import load_conversation, save_conversation

# Import the Secrets Manager helper (defined in aws_secrets.py)
# Note: named aws_secrets.py to avoid shadowing Python's built-in secrets module
from aws_secrets import get_secret

# Load .env file for local development (has no effect in Lambda where env vars are set directly)
load_dotenv()

app = FastAPI()

# ─── Runtime Configuration ────────────────────────────────────────────────────
# These values come from Lambda environment variables (set in lambda.tf).
# In local dev, they fall back to safe defaults.

# USE_DYNAMODB controls which storage backend is used.
# Set to "true" by Terraform in lambda.tf; "false" by default for local dev.
USE_DYNAMODB = os.getenv("USE_DYNAMODB", "false").lower() == "true"

BEDROCK_REGION   = os.getenv("BEDROCK_REGION", "us-east-1")
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "global.amazon.nova-2-lite-v1:0")

# ─── CORS Configuration ───────────────────────────────────────────────────────
# CORS (Cross-Origin Resource Sharing) controls which websites can call this API.
# The browser enforces this: a script at origin A is blocked from calling API at origin B
# unless B explicitly lists A as an allowed origin.
#
# In production (USE_DYNAMODB=True):
#   Fetch CORS_ORIGINS from Secrets Manager at Lambda startup.
#   The secret is named by the SECRET_NAME environment variable (set by Terraform).
#   Example secret value: {"CORS_ORIGINS": "https://d1234abcd.cloudfront.net"}
#
# In local development (USE_DYNAMODB=False):
#   Read CORS_ORIGINS from the environment / .env file.
#   Defaults to "http://localhost:3000" so the local Next.js dev server works.
#
# Note: API Gateway also enforces CORS at the gateway level (configured in api_gateway.tf).
# This middleware adds the same policy inside FastAPI for defence-in-depth:
# if a request somehow bypasses API Gateway, FastAPI still enforces the rule.

if USE_DYNAMODB:
    # Fetch the secret that contains CORS_ORIGINS.
    # SECRET_NAME is set by Terraform: e.g., "twin/config-dev"
    secret_name = os.getenv("SECRET_NAME", "twin/config")
    config = get_secret(secret_name)

    # If the key exists in the secret, use it; otherwise fall back to localhost.
    # .split(",") supports multiple origins like "https://a.net,https://b.net"
    cors_origins = config.get("CORS_ORIGINS", "http://localhost:3000").split(",")
else:
    # Local dev: read from environment variable or .env file
    cors_origins = os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")

# Register the CORS middleware with FastAPI.
# This adds the appropriate Access-Control-Allow-Origin headers to every response.
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# ─── Bedrock Client ───────────────────────────────────────────────────────────
# Initialised once at module load — reused for every request (warm starts benefit from this).
bedrock_client = boto3.client(
    service_name="bedrock-runtime",
    region_name=BEDROCK_REGION
)


# ─── Request / Response Models ────────────────────────────────────────────────
# Pydantic models define the expected shape of incoming and outgoing JSON.

class ChatRequest(BaseModel):
    message: str
    session_id: Optional[str] = None  # If None, server generates a new UUID


class ChatResponse(BaseModel):
    response: str
    session_id: str  # Always returned so the frontend can maintain session continuity


# ─── Bedrock Helper ───────────────────────────────────────────────────────────

def call_bedrock(conversation: List[Dict], user_message: str) -> str:
    """
    Send the conversation history plus the new user message to Bedrock,
    and return the AI assistant's response text.

    Parameters:
        conversation:  list of previous message dicts with "role" and "content"
        user_message:  the new message the user just sent

    The last 50 messages of conversation history are included to stay within
    Bedrock's context limit while preserving meaningful recent context.
    """
    # Build the message list in the format Bedrock's converse API expects:
    # [{"role": "user", "content": [{"text": "..."}]}, {"role": "assistant", ...}, ...]
    messages = []
    for msg in conversation[-50:]:  # Only the last 50 messages to avoid token limits
        messages.append({
            "role": msg["role"],
            "content": [{"text": msg["content"]}]
        })

    # Append the new user message at the end of the list
    messages.append({
        "role": "user",
        "content": [{"text": user_message}]
    })

    try:
        # Call Bedrock using the converse API.
        # The system prompt (from context.py) gives the AI its Digital Twin persona.
        # It is passed via the "system" parameter — the correct approach that keeps
        # it separate from the conversation messages list.
        response = bedrock_client.converse(
            modelId=BEDROCK_MODEL_ID,
            system=[{"text": prompt()}],
            messages=messages,
            inferenceConfig={
                "maxTokens":   2000,   # Maximum length of the AI response
                "temperature": 0.7,   # 0 = deterministic, 1 = very creative
                "topP":        0.9    # Nucleus sampling — controls diversity of word choices
            }
        )

        # Extract the response text from the nested Bedrock response structure
        return response["output"]["message"]["content"][0]["text"]

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        if error_code == "ValidationException":
            raise HTTPException(status_code=400, detail="Invalid message format for Bedrock")
        elif error_code == "AccessDeniedException":
            raise HTTPException(status_code=403, detail="Access denied to Bedrock model")
        else:
            raise HTTPException(status_code=500, detail=f"Bedrock error: {str(e)}")


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.get("/health")
async def health_check():
    """
    Health check endpoint — used in Part 7 to verify the deployment is working.
    Returns "storage: dynamodb" when running in Lambda, "storage: local" when running locally.
    """
    return {
        "status":         "healthy",
        "storage":        "dynamodb" if USE_DYNAMODB else "local",
        "bedrock_model":  BEDROCK_MODEL_ID,
        "workspace":      os.getenv("ENVIRONMENT", "local")
    }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    """
    Main chat endpoint — receives a user message and returns the AI's response.

    Steps:
      1. Generate a session ID if the frontend didn't provide one
      2. Load existing conversation history from DynamoDB (or empty list if new session)
      3. Call Bedrock with the full conversation history + the new message
      4. Append both the user message and AI response to the history
      5. Save the updated history back to DynamoDB
      6. Return the AI response and session ID to the frontend
    """
    try:
        # If the frontend hasn't provided a session_id, generate one.
        # The frontend stores this and sends it back on every follow-up message,
        # allowing Bedrock to see the full conversation context.
        session_id = request.session_id or str(uuid.uuid4())

        # Load conversation history from the appropriate backend:
        #   - USE_DYNAMODB=True  → call DynamoDB (deployed environment)
        #   - USE_DYNAMODB=False → use empty list (local dev, no persistence)
        if USE_DYNAMODB:
            conversation = load_conversation(session_id)
        else:
            conversation = []  # Local dev: no persistence between requests

        # Call Bedrock with the conversation history + new user message
        assistant_response = call_bedrock(conversation, request.message)

        # Append the user message and AI response to the conversation history.
        # Both are timestamped so you can see the order of messages in DynamoDB.
        conversation.append({
            "role":      "user",
            "content":   request.message,
            "timestamp": datetime.now().isoformat()
        })
        conversation.append({
            "role":      "assistant",
            "content":   assistant_response,
            "timestamp": datetime.now().isoformat()
        })

        # Save the updated conversation back to DynamoDB (production only).
        # The full updated list (including new messages) is saved as one item.
        if USE_DYNAMODB:
            save_conversation(session_id, conversation)

        return ChatResponse(response=assistant_response, session_id=session_id)

    except HTTPException:
        raise  # Re-raise FastAPI HTTP exceptions as-is (already formatted correctly)
    except Exception as e:
        print(f"Error in chat endpoint: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    # Local development entry point: run with "python server.py" or "uvicorn server:app --reload"
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
