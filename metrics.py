import os
import json
from datetime import datetime
import urllib3
import boto3
from boto3.dynamodb.conditions import Key

table = boto3.resource('dynamodb').Table(os.environ['DYNAMO_TABLE'])

bad_response = {
    "statusCode": 403,
    "headers": {"content-type": "application/json"},
    "body": json.dumps({ "response" : "bad" })
}

def logger_handler(event, context):
    current_date = datetime.today().strftime('%Y-%m-%d')
    num_zones = num_regions = num_areas = num_meetings = num_groups = 0
    req = urllib3.PoolManager().request("GET", 'https://tomato.bmltenabled.org/rest/v1/rootservers/')
    root_servers = json.loads(req.data.decode())

    for root in root_servers:
        num_zones += root['num_zones']
        num_areas += root['num_areas']
        num_groups += root['num_groups']
        num_regions += root['num_regions']
        num_meetings += root['num_meetings']

    table.put_item(Item={
        'date': current_date,
        'num_zones': str(num_zones),
        'num_areas': str(num_areas),
        'num_groups': str(num_groups),
        'num_regions': str(num_regions),
        'num_meetings': str(num_meetings)
    })


def api_handler(event, context):
    print(event)
    path = event.get("path")
    if not path.startswith("/metrics"):
        print("bad path")
        return bad_response

    response = table.query(
        KeyConditionExpression=Key('date').eq('2021-06-27')
    )
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(response['Items'])
    }
