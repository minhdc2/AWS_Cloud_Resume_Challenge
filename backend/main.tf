terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  # backend "s3" {
  #   bucket = "myresume-us-east-1" # change to name of your bucket
  #   region = "us-east-1"          # change to your region
  #   key    = "terraform.tfstate"
  # }

  required_version = ">= 1.2.0"
}

# provider "aws" {
#   # Configuration options
#   region = "us-east-1" # (1)
# }

# 1. Configure DynamoDB
resource "aws_dynamodb_table" "VisitDetails" {
  name           = "VisitDetails"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key         = "timestamp"

  attribute {
    name = "timestamp"
    type = "S"
  }

  tags = {
    Name        = "VisitDetails"
    Environment = "production"
  }
}

module  "table_autoscaling" {
   source = "snowplow-devops/dynamodb-autoscaling/aws" 
   table_name = aws_dynamodb_table.VisitDetails.name
}

# 2. Configure IAM policy allowing Lambda function to connect to DynamoDB
data "aws_iam_policy_document" "BasicReadWriteDynamoDB" {
  statement {
    sid = "VisualEditor0"

    effect = "Allow"

    actions = ["dynamodb:BatchGetItem",
                "dynamodb:ConditionCheckItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem",
                "dynamodb:GetItem",
                "dynamodb:Scan",
                "dynamodb:Query",
                "dynamodb:UpdateItem",
                "dynamodb:GetRecords"]
    
    resources = [aws_dynamodb_table.VisitDetails.arn] # (2)
  }
}

resource "aws_iam_policy" "BasicReadWriteDynamoDB2" { # (3)
  name   = "BasicReadWriteDynamoDB2" # (4)
  path   = "/"
  policy = data.aws_iam_policy_document.BasicReadWriteDynamoDB.json
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "BasicLambdaToDynamodbRole" {
  name               = "BasicLambdaToDynamodbRole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "AttachPolicyToRole" {
  role       = aws_iam_role.BasicLambdaToDynamodbRole.name
  policy_arn = aws_iam_policy.BasicReadWriteDynamoDB2.arn
}

# 3. Configure Lambda functions for POST and GET Requests
data "archive_file" "getVisitsCountFromDynamodb" {
  type        = "zip"
  source_file = "${path.module}/lambda/getVisitsCountFromDynamodb.py"
  output_path = "${path.module}/lambda/zip/getVisitsCountFromDynamodb.zip"
}

data "archive_file" "updateVisitDetailsToDynamodb" {
  type        = "zip"
  source_file = "${path.module}/lambda/updateVisitDetailsToDynamodb.py"
  output_path = "${path.module}/lambda/zip/updateVisitDetailsToDynamodb.zip"
}

resource "aws_lambda_function" "getVisitsCountFromDynamodb" {
  filename      = "${path.module}/lambda/zip/getVisitsCountFromDynamodb.zip"
  function_name = "getVisitsCountFromDynamodb"
  role          = aws_iam_role.BasicLambdaToDynamodbRole.arn
  handler       = "getVisitsCountFromDynamodb.lambda_handler"

  source_code_hash = data.archive_file.getVisitsCountFromDynamodb.output_base64sha256

  runtime = "python3.8"
}

resource "aws_lambda_function" "updateVisitDetailsToDynamodb" {
  filename      = "${path.module}/lambda/zip/updateVisitDetailsToDynamodb.zip"
  function_name = "updateVisitDetailsToDynamodb"
  role          = aws_iam_role.BasicLambdaToDynamodbRole.arn
  handler       = "updateVisitDetailsToDynamodb.lambda_handler"

  source_code_hash = data.archive_file.updateVisitDetailsToDynamodb.output_base64sha256

  runtime = "python3.8"
}

# 4. Configure API Gateway to be integrated with Lambda functions
resource "aws_api_gateway_rest_api" "ResumeVisitsCount" {
  name        = "ResumeVisitsCount"
  description = ""
}

# 4.1 Integrate API POST Request with Lambda function updateVisitDetailsToDynamodb
resource "aws_api_gateway_resource" "post" {
  rest_api_id = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
  parent_id   = "${aws_api_gateway_rest_api.ResumeVisitsCount.root_resource_id}"
  path_part   = "post"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id   = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
  resource_id   = "${aws_api_gateway_resource.post.id}"
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "updateVisitDetailsToDynamodb" {
  rest_api_id = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
  resource_id = "${aws_api_gateway_method.post.resource_id}"
  http_method = "${aws_api_gateway_method.post.http_method}"

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "${aws_lambda_function.updateVisitDetailsToDynamodb.invoke_arn}"
}

resource "aws_api_gateway_integration_response" "updateVisitDetailsToDynamodb" {
    rest_api_id = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
    resource_id = "${aws_api_gateway_method.post.resource_id}"
    http_method = aws_api_gateway_method.post.http_method
    status_code = 200

    response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
        "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
        "method.response.header.Access-Control-Allow-Origin" = "'*'"
    }

    depends_on = [
        aws_api_gateway_integration.updateVisitDetailsToDynamodb,
        aws_api_gateway_method_response.updateVisitDetailsToDynamodb,
    ]
}

resource "aws_api_gateway_method_response" "updateVisitDetailsToDynamodb" {
  rest_api_id = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
  resource_id = "${aws_api_gateway_method.post.resource_id}"
  http_method = aws_api_gateway_method.post.http_method
  status_code = 200

  response_parameters = {
        "method.response.header.Access-Control-Allow-Origin" = true,
        "method.response.header.Access-Control-Allow-Methods" = true,
        "method.response.header.Access-Control-Allow-Headers" = true,
    }

  response_models = {
    "application/json" = "Empty"
  }

  depends_on = [
    aws_api_gateway_method.post,
  ]
}

resource "aws_api_gateway_deployment" "updateVisitDetailsToDynamodb" {
  depends_on = [
    aws_api_gateway_integration.updateVisitDetailsToDynamodb,
  ]

  rest_api_id = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
  stage_name  = "dev"
}

# 4.2 Integrate API GET Request with Lambda function
resource "aws_api_gateway_resource" "get" {
  rest_api_id = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
  parent_id   = "${aws_api_gateway_rest_api.ResumeVisitsCount.root_resource_id}"
  path_part   = "resource"
}

resource "aws_api_gateway_method" "get" {
  rest_api_id   = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
  resource_id   = "${aws_api_gateway_resource.get.id}"
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "getVisitsCountFromDynamodb" {
  rest_api_id = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
  resource_id = "${aws_api_gateway_method.get.resource_id}"
  http_method = "${aws_api_gateway_method.get.http_method}"

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "${aws_lambda_function.getVisitsCountFromDynamodb.invoke_arn}"
  request_templates = {
    "application/json" = <<EOF
#set($inputRoot = $input.path('$'))
{}
    EOF
  }
}

resource "aws_api_gateway_integration_response" "getVisitsCountFromDynamodb" {
    rest_api_id = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
    resource_id = "${aws_api_gateway_method.get.resource_id}"
    http_method = aws_api_gateway_method.get.http_method
    status_code = 200

    response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
        "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
        "method.response.header.Access-Control-Allow-Origin" = "'*'"
    }

    depends_on = [
        aws_api_gateway_integration.getVisitsCountFromDynamodb,
        aws_api_gateway_method_response.getVisitsCountFromDynamodb,
    ]
}

resource "aws_api_gateway_method_response" "getVisitsCountFromDynamodb" {
    rest_api_id = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
    resource_id = "${aws_api_gateway_method.get.resource_id}"
    http_method = aws_api_gateway_method.get.http_method
    status_code = 200

    response_parameters = {
        "method.response.header.Access-Control-Allow-Origin" = true,
        "method.response.header.Access-Control-Allow-Methods" = true,
        "method.response.header.Access-Control-Allow-Headers" = true,
    }

    response_models = {
        "application/json" = "Empty"
    }

    depends_on = [
        aws_api_gateway_method.get,
    ]
}

# 5. Deploy API
resource "aws_api_gateway_deployment" "getVisitsCountFromDynamodb" {
    depends_on = [
        aws_api_gateway_integration.getVisitsCountFromDynamodb,
    ]

    rest_api_id = "${aws_api_gateway_rest_api.ResumeVisitsCount.id}"
    stage_name  = "dev"
}

# 6. Grant Lambda Invoke permission to API Gateway
resource "aws_lambda_permission" "apigw_post" {
    statement_id  = "AllowAPIGatewayInvoke1"
    action        = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.updateVisitDetailsToDynamodb.function_name}"
    principal     = "apigateway.amazonaws.com"
    source_arn = "${aws_api_gateway_rest_api.ResumeVisitsCount.execution_arn}/*/POST/${aws_api_gateway_resource.post.path_part}"
}

resource "aws_lambda_permission" "apigw_get" {
    statement_id  = "AllowAPIGatewayInvoke2"
    action        = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.getVisitsCountFromDynamodb.function_name}"
    principal     = "apigateway.amazonaws.com"
    source_arn = "${aws_api_gateway_rest_api.ResumeVisitsCount.execution_arn}/*/GET/${aws_api_gateway_resource.get.path_part}"
}


