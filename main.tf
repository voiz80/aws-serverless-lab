provider "aws" {
    region  = "eu-central-1"
    profile = "default"
}

data "aws_iam_policy_document" "dynamoDbCloudWatchLogs" {
    statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "dynamoDbCloudWatchLogs" {
   name         = "dynamoDbCloudWatchLogs"
   description  = "Custom policy with permission to DynamoDB and CloudWatch Logs. This custom policy has the permissions that the function needs to write data to DynamoDB and upload logs"
   policy       = "${file("policy.json")}"
}


resource "aws_iam_role" "lambda-apigateway-role" {
  name               = "lambda-apigateway-role"
  assume_role_policy = data.aws_iam_policy_document.dynamoDbCloudWatchLogs.json
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.lambda-apigateway-role.name
  policy_arn = aws_iam_policy.dynamoDbCloudWatchLogs.arn
}

data "archive_file" "python_lambda_package" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "LambdaFunctionOverHttps" {
   
    function_name                  = "LambdaFunctionOverHttps"
    filename                       = "lambda_function_payload.zip"
    source_code_hash               = data.archive_file.python_lambda_package.output_base64sha256
    handler                        = "lambda_function.lambda_handler"
    role                           = aws_iam_role.lambda-apigateway-role.arn
    runtime                        = "python3.7"
    timeout                        = 3

}


resource "aws_dynamodb_table" "lambda-apigateway" {
    
    billing_mode                = "PROVISIONED"
    hash_key                    = "id"
    name                        = "lambda-apigateway"
    read_capacity               = 1
    stream_enabled              = false
    write_capacity              = 1

    attribute {
        name                    = "id"
        type                    = "S"
    }

}

resource "aws_api_gateway_rest_api" "DynamoDBOperations" {
    api_key_source               = "HEADER"
    name                         = "DynamoDBOperations"
    put_rest_api_mode            = "overwrite"
    endpoint_configuration {
        types                    = ["REGIONAL"]
    }
}

resource "aws_api_gateway_resource" "dynamodbmanager" {
    rest_api_id = aws_api_gateway_rest_api.DynamoDBOperations.id
    parent_id   = aws_api_gateway_rest_api.DynamoDBOperations.root_resource_id
    path_part   = "dynamodbmanager"
}

resource "aws_api_gateway_method" "POST"{
    authorization        = "NONE"
    http_method          = "POST"
    resource_id          = aws_api_gateway_resource.dynamodbmanager.id
    rest_api_id          = aws_api_gateway_rest_api.DynamoDBOperations.id
}

resource "aws_api_gateway_integration" "lambda" {
    connection_type         = "INTERNET"
    http_method             = aws_api_gateway_method.POST.http_method
    integration_http_method = "POST"
    resource_id             = aws_api_gateway_resource.dynamodbmanager.id
    rest_api_id             = aws_api_gateway_rest_api.DynamoDBOperations.id
    type                    = "AWS"
    uri                     = aws_lambda_function.LambdaFunctionOverHttps.invoke_arn
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.DynamoDBOperations.id
  resource_id = aws_api_gateway_resource.dynamodbmanager.id
  http_method = aws_api_gateway_method.POST.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
    }
}

resource "aws_api_gateway_integration_response" "MyDemoIntegrationResponse" {
  rest_api_id = aws_api_gateway_rest_api.DynamoDBOperations.id
  resource_id = aws_api_gateway_resource.dynamodbmanager.id
  http_method = aws_api_gateway_method.POST.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

}

resource "aws_api_gateway_deployment" "Prod" {
    depends_on      = [ aws_api_gateway_integration.lambda ]
    rest_api_id     = aws_api_gateway_rest_api.DynamoDBOperations.id
    stage_name      = "Prod"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.LambdaFunctionOverHttps.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.DynamoDBOperations.execution_arn}/*/POST/dynamodbmanager"
}

output "aws_api_gateway_deployment" {
    description = "Deployment invoke url"
    value       = aws_api_gateway_deployment.Prod.invoke_url
}