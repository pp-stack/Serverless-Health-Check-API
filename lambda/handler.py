import json
import uuid

def lambda_handler(event, context):
    # Basic validation: require JSON body with 'payload' key
    body = None
    try:
        if event.get('body'):
            body = json.loads(event['body'])
        else:
            body = event
    except Exception:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid JSON body'})
        }

    if not isinstance(body, dict) or 'payload' not in body:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': "Missing required key 'payload'"})
        }

    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': 'healthy',
            'message': 'Request processed.',
            'id': item_id
        })
    }
