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

    http_method = event.get('httpMethod') or event.get('requestContext', {}).get('http', {}).get('method')

    # Parse body (API Gateway v1/v2 compatibility)
    body = {}
    if isinstance(event.get('body'), str) and event['body']:
        try:
            body = json.loads(event['body'])
        except Exception:
            return _response(400, {'error': 'Invalid JSON body'})

    # POST requests must carry a JSON body containing a 'payload' key.
    # GET is treated as a plain liveness check and does not require one.
    if http_method == 'POST' and (not isinstance(body, dict) or 'payload' not in body):
        return _response(400, {'error': "Missing required key 'payload'"})

    # Prepare item
    item_id = str(uuid.uuid4())
    timestamp = datetime.datetime.utcnow().isoformat() + 'Z'
    item = {
        'id': item_id,
        'method': http_method,
        'payload': body.get('payload') if isinstance(body, dict) else None,
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
