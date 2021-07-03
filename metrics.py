import os
import json
from datetime import datetime
import urllib3
import boto3
from boto3.dynamodb.conditions import Key

table = boto3.resource('dynamodb').Table(os.environ['DYNAMO_TABLE'])
current_date = datetime.today().strftime('%Y-%m-%d')


def bad_response(message):
    return {
        "statusCode": 403,
        "headers": {
            "content-type": "application/json",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "OPTIONS,POST,GET"
        },
        "body": json.dumps({"error_response": message})
    }


def logger_handler(event, context):
    num_zones = num_regions = num_areas = num_meetings = num_groups = 0
    req = urllib3.PoolManager().request(
        "GET", 'https://tomato.bmltenabled.org/rest/v1/rootservers/')
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
    print(json.dumps(event))
    path = event.get("path")
    if not path.startswith("/metrics"):
        return bad_response("bad path")
    params = event.get("queryStringParameters")
    start_date = params.get("start_date") if params and params.get(
        "start_date") else "2021-06-27"
    end_date = params.get("end_date") if params and params.get(
        "end_date") else current_date
    fe = Key('date').between(start_date, end_date)
    response = table.scan(FilterExpression=fe)
    sorted_response = sorted(response['Items'], key=lambda k: k['date'])

    return {
        "statusCode": 200,
        "headers": {
            "content-type": "application/json",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "OPTIONS,POST,GET"
        },
        "body": json.dumps(sorted_response)
    }
