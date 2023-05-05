import json
import boto3
import datetime

def lambda_handler(event, context):
    
    now = datetime.datetime.now().strftime('%d-%b-%y %I:%M:%S %p')
    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table("VisitDetails")
    if table.scan()["Items"]:
        # get VisitsCount value
        curr_cnt = str(table.scan()["Count"])
    else:
        curr_cnt = 0
    
    # form response's body
    item = {
        "name": "GET Request",
        "visitsCount": curr_cnt,
        "recentVisitTime": now
    }
    
    # construct http response object
    responseObject = {}
    responseObject["statusCode"] = 200
    responseObject["headers"] = {}
    responseObject["headers"]["Content-Type"] = "application/json"
    responseObject["headers"]["Access-Control-Allow-Origin"] = "*"
    responseObject["body"] = json.dumps(item)

    return responseObject

