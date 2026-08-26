import json
import uuid
import os
import datetime
import boto3
from botocore.exceptions import ClientError

TABLE_ENV_VAR = "REQUESTS_TABLE"

_dynamodb = None

def _get_table():
    global _dynamodb
    if _dynamodb is None:
        table_name = os.environ.get(TABLE_ENV_VAR)
        if not table_name:
            raise RuntimeError(f"Environment variable {TABLE_ENV_VAR} is required")
        ddb = boto3.resource('dynamodb')
        _dynamodb = ddb.Table(table_name)
    return _dynamodb

def lambda_handler(event, context):
    # Log the incoming raw event for observability
    print('Received event:', json.dumps(event))

    # Parse body (API Gateway v1/v2 compatibility)
    body = None
    try:
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        elif event.get('body') is None and event.get('queryStringParameters'):
            # Allow simple GET with query params encoded as body-like dict
            body = event.get('queryStringParameters')
        else:
            body = event.get('body') or {}
    except Exception:
        return _response(400, {'error': 'Invalid JSON body'})

    # Validate presence of 'payload'
    if not isinstance(body, dict) or 'payload' not in body:
        return _response(400, {'error': "Missing required key 'payload'"})

    # Prepare item
    item_id = str(uuid.uuid4())
    timestamp = datetime.datetime.utcnow().isoformat() + 'Z'
    item = {
        'id': item_id,
        'payload': body.get('payload'),
        'received_at': timestamp
    }

    # Attempt to save to DynamoDB
    try:
        table = _get_table()
        table.put_item(Item=item)
        print('Saved item to DynamoDB:', item)
    except ClientError as e:
        print('DynamoDB error:', str(e))
        return _response(500, {'error': 'Failed to save item'})
    except Exception as e:
        print('Unexpected error:', str(e))
        return _response(500, {'error': 'Internal error'})

    return _response(200, {
        'status': 'healthy',
        'message': 'Request processed and saved.',
        'id': item_id
    })


def _response(status_code, body_obj):
    return {
        'statusCode': status_code,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(body_obj)
    }
