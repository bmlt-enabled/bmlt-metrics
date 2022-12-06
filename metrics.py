import os
import json
from datetime import datetime
import urllib3
import boto3
from boto3.dynamodb.conditions import Key

dynamo = boto3.resource('dynamodb')
table = dynamo.Table(os.environ['DYNAMO_TABLE'])
table_individual = dynamo.Table(os.environ['DYNAMO_TABLE_INDIVIDUAL'])
current_date = datetime.today().strftime('%Y-%m-%d')
current_date_hash = datetime.today().strftime('%Y%m%d')

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
        num_zones = num_regions = num_areas = num_meetings = num_groups = num_in_person = num_virtual = num_hybrid = 0
        req = urllib3.PoolManager().request(
            "GET", 'https://tomato.bmltenabled.org/main_server/api/v1/rootservers/')
        root_servers = json.loads(req.data.decode())

        for root in root_servers:
            num_zones += root['statistics']['serviceBodies']['numZones']
            num_areas += root['statistics']['serviceBodies']['numAreas']
            num_groups += root['statistics']['serviceBodies']['numGroups']
            num_regions += root['statistics']['serviceBodies']['numRegions']
            num_meetings += root['statistics']['meetings']['numTotal']
            num_in_person += root['statistics']['meetings']['numInPerson']
            num_virtual += root['statistics']['meetings']['numVirtual']
            num_hybrid += root['statistics']['meetings']['numHybrid']
            table_individual.put_item(Item={
                'id' : current_date_hash + str(root['sourceId']),
                'date': current_date,
                'name': root['name'],
                'source_id': str(root['sourceId']),
                'num_zones': str(root['statistics']['serviceBodies']['numZones']),
                'num_areas': str(root['statistics']['serviceBodies']['numAreas']),
                'num_groups': str(root['statistics']['serviceBodies']['numGroups']),
                'num_regions': str(root['statistics']['serviceBodies']['numRegions']),
                'num_meetings': str(root['statistics']['meetings']['numTotal']),
                'num_in_person': str(root['statistics']['meetings']['numInPerson']),
                'num_virtual': str(root['statistics']['meetings']['numVirtual']),
                'num_hybrid': str(root['statistics']['meetings']['numHybrid'])
            })

    table.put_item(Item={
        'date': current_date,
        'num_zones': str(num_zones),
        'num_areas': str(num_areas),
        'num_groups': str(num_groups),
        'num_regions': str(num_regions),
        'num_meetings': str(num_meetings),
        'num_in_person': str(num_in_person),
        'num_virtual': str(num_virtual),
        'num_hybrid': str(num_hybrid)
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
