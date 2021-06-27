import os
import json
from datetime import datetime
from urllib.request import *
import boto3

dynamo = boto3.resource('dynamodb').Table(os.environ['DYNAMO_TABLE'])
tomato_url = "https://tomato.bmltenabled.org/rest/v1/rootservers/"


def lambda_handler(event, context):
    current_date = datetime.today().strftime('%Y-%m-%d')
    num_zones = num_regions = num_areas = num_meetings = num_groups = 0

    req = Request(url=tomato_url, headers={}, method='GET')
    with urlopen(req) as res:
        body = res.read().decode()

    root_servers = json.loads(body)

    for root in root_servers:
        num_zones    += root['num_zones']
        num_areas    += root['num_areas']
        num_groups   += root['num_groups']
        num_regions  += root['num_regions']
        num_meetings += root['num_meetings']

    num = {
        'date'         : current_date,
        'num_zones'    : num_zones,
        'num_areas'    : num_areas,
        'num_groups'   : num_groups,
        'num_regions'  : num_regions,
        'num_meetings' : num_meetings
    }
    print(json.dumps(num))
    dynamo.put_item(Item=num)
