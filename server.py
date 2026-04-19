from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
import os
from typing import Optional, List, Dict
import uuid
from datetime import datetime
import boto3
from botocore.exceptions import ClientError

from dynamo_memory import load_conversation, save_conversation
from app_secrets import get_secret

app = FastAPI()

USE_DYNAMODB = os.getenv("USE_DYNAMODB", "false").lower() == "true"
BEDROCK_REGION   = os.getenv("BEDROCK_REGION", "us-east-1")
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "global.amazon.nova-2-lite-v1:0")

if USE_DYNAMODB:
    secret_name = os.getenv("SECRET_NAME", "essay-coach/config-dev")
    config = get_secret(secret_name)
    cors_origins = config.get("CORS_ORIGINS", "http://localhost:3000").split(",")
else:
    cors_origins = os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

bedrock_client = boto3.client(
    service_name="bedrock-runtime",
    region_name=BEDROCK_REGION
)


# ─── Request / Response Models ────────────────────────────────────────────────

class EssayRequest(BaseModel):
    essay_text:       str           = Field(..., min_length=50)
    assignment_brief: str           = Field(..., min_length=10)
    essay_type:       str           = Field(...)
    education_level:  str           = Field(...)
    word_limit:       Optional[int] = Field(None, gt=0)
    session_id:       Optional[str] = None


class FeedbackResponse(BaseModel):
    response:   str
    session_id: str


# ─── Prompts ──────────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """
You are an expert academic writing coach with over 20 years of experience helping students at all levels — from high school through graduate school — improve their writing. Your role is to provide structured, constructive, and actionable feedback that helps writers understand both what they did well and exactly where and how to improve.

When a student submits their essay, you will analyse it carefully and respond with exactly three sections, each marked with a ## Markdown heading. Never deviate from this structure.

## Strengths
Identify 3 to 5 specific things the essay does well. Be precise — cite actual phrases or sentences from the essay. Explain WHY each strength works. Your tone should be encouraging and specific. Avoid vague praise like "good job." Address this section to the student in second person (you, your).

## Areas to Improve
Identify 3 to 5 specific weaknesses with actionable suggestions. For each issue: (a) describe the problem clearly, (b) show a brief example from the essay, and (c) explain concretely how to fix it. Be honest but constructive — frame feedback as opportunities rather than failures. Adapt the complexity of your language to the student's education level: more explanatory for high school, more technical for graduate. Use second person (you, your).

## Suggested Rewrite
Provide a rewritten version of the essay's introduction (first paragraph only). Your rewrite must demonstrate the improvements you identified — a stronger hook, a clearer thesis, tighter structure. Preserve the student's original ideas and voice; improve only the execution. After the rewrite, add exactly one sentence explaining the most significant change you made and why it strengthens the essay.

Critical rules you must always follow:
1. Do not invent arguments, claims, or evidence not present in the student's original essay.
2. If the essay is fewer than 80 words, tell the student it is too short to evaluate properly and ask them to submit a fuller draft.
3. Always produce all three ## sections, even if one has limited material.
4. Never address the student by a generic name — use "you" and "your" throughout.
""".strip()


def user_prompt_for(record: EssayRequest) -> str:
    word_limit_line = f"Target Word Limit: {record.word_limit} words\n" if record.word_limit else ""
    return (
        f"Please review this {record.essay_type} essay submitted by a {record.education_level} student.\n\n"
        f"Assignment Brief:\n{record.assignment_brief}\n\n"
        f"{word_limit_line}"
        f"Essay to Review:\n{record.essay_text}\n\n"
        f"Provide structured feedback with exactly three sections: "
        f"## Strengths, ## Areas to Improve, and ## Suggested Rewrite."
    )


# ─── Bedrock Helper ───────────────────────────────────────────────────────────

def call_bedrock(user_message: str) -> str:
    messages = [{"role": "user", "content": [{"text": user_message}]}]
    try:
        response = bedrock_client.converse(
            modelId=BEDROCK_MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=messages,
            inferenceConfig={"maxTokens": 3000, "temperature": 0.5, "topP": 0.9}
        )
        return response["output"]["message"]["content"][0]["text"]
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        if error_code == "ValidationException":
            raise HTTPException(status_code=400, detail="Invalid request format for Bedrock")
        elif error_code == "AccessDeniedException":
            raise HTTPException(status_code=403, detail="Access denied to Bedrock model")
        else:
            raise HTTPException(status_code=500, detail=f"Bedrock error: {str(e)}")


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.get("/health")
def health_check():
    return {"status": "healthy", "version": "1.0"}


@app.post("/api")
async def process(record: EssayRequest):
    try:
        session_id = record.session_id or str(uuid.uuid4())

        conversation = load_conversation(session_id) if USE_DYNAMODB else []

        user_message = user_prompt_for(record)
        assistant_response = call_bedrock(user_message)

        conversation.append({"role": "user",      "content": user_message,       "timestamp": datetime.now().isoformat()})
        conversation.append({"role": "assistant",  "content": assistant_response, "timestamp": datetime.now().isoformat()})

        if USE_DYNAMODB:
            save_conversation(session_id, conversation)

        def event_stream():
            for line in assistant_response.split("\n"):
                yield f"data: {line}\n"
            yield "\n"

        return StreamingResponse(event_stream(), media_type="text/event-stream")

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in /api endpoint: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
