import json
import boto3
import datetime

def lambda_handler(event, context):
    
    # setup
    add = event["add"]
    now = datetime.datetime.now().strftime('%d-%b-%y %I:%M:%S %p')
    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table("VisitDetails")
    
    # add a new record
    item = {
        "visit": str(add),
        "timestamp": now
    }
        
    table.put_item(
        Item=item
    )
    
    # construct http response object
    responseObject = {}
    responseObject['statusCode'] = 200
    responseObject['headers'] = {}
    responseObject['headers']['Content-Type'] = 'application/json'
    responseObject['body'] = json.dumps(item)

    return responseObject
