import boto3
import os
from datetime import datetime, timedelta
from typing import List, Dict

_dynamodb = None
_table = None


def _get_table():
    global _dynamodb, _table
    if _table is None:
        _dynamodb = boto3.resource("dynamodb", region_name=os.getenv("AWS_REGION", "us-east-1"))
        table_name = os.getenv("DYNAMODB_TABLE", "twin-dev-conversations")
        _table = _dynamodb.Table(table_name)
    return _table


def load_conversation(session_id: str) -> List[Dict]:
    try:
        table = _get_table()
        response = table.get_item(Key={"session_id": session_id})
        if "Item" in response:
            return response["Item"].get("messages", [])
        return []
    except Exception as e:
        print(f"Error loading conversation from DynamoDB: {e}")
        return []


def save_conversation(session_id: str, messages: List[Dict]) -> None:
    try:
        table = _get_table()
        ttl_timestamp = int((datetime.utcnow() + timedelta(days=30)).timestamp())
        table.put_item(Item={
            "session_id":  session_id,
            "messages":    messages,
            "updated_at":  datetime.utcnow().isoformat(),
            "ttl":         ttl_timestamp
        })
    except Exception as e:
        print(f"Error saving conversation to DynamoDB: {e}")
