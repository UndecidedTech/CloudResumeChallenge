resource "aws_iam_role" "lambda_exec_role" {
  provider = aws.us-east-1
  name     = "http-crud-tutorial-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

}
#Zip lambda for upload

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../../api/src/handlers/bump-count"
  output_path = "../../api/src/handlers/lambda_function.zip"
}


resource "aws_lambda_function" "my_resume_lambda" {
  provider      = aws.us-east-1
  function_name = "my_resume_lambda"
  handler       = "index.handler"
  runtime       = "nodejs22.x"
  filename      = data.archive_file.lambda_zip.output_path
  role          = aws_iam_role.lambda_exec_role.arn
}

resource "aws_api_gateway_rest_api" "api" {
  provider = aws.us-east-1
  name     = "CloudResume" # IMPORTANT: Replace with the actual name of
}

resource "aws_api_gateway_resource" "count" {
  provider    = aws.us-east-1
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "count"
}

resource "aws_api_gateway_method" "count_get" {
  provider      = aws.us-east-1
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.count.id
  http_method   = "GET"
  authorization = "NONE" # Change if you use an authorizer
}



resource "aws_api_gateway_integration" "count_get_lambda" {
  provider                = aws.us-east-1
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.count.id
  http_method             = aws_api_gateway_method.count_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  # This assumes you have a lambda resource named "my_lambda" defined
  uri = aws_lambda_function.my_resume_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "api_deployment" {
  provider    = aws.us-east-1
  rest_api_id = aws_api_gateway_rest_api.api.id

  # This ensures the deployment is re-created when the integration changes
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_integration.count_get_lambda))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  provider      = aws.us-east-1
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "CloudResumeV1"
}

resource "aws_lambda_permission" "apigw_lambda" {
  provider      = aws.us-east-1
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_resume_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"

}

resource "aws_dynamodb_table" "visitor_counter" {
  provider     = aws.us-east-1
  name         = "CloudResume"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S" # "S" stands for String
  }

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-visitor-counter-table"
  })
}



resource "aws_iam_policy" "lambda_dynamodb_policy" {
  provider = aws.us-east-1
  name     = "${var.naming_prefix}-lambda-dynamodb-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.visitor_counter.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  provider   = aws.us-east-1
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_policy" "lambda_cloudwatch_logs_policy" {
  provider = aws.us-east-1
  name     = "${var.naming_prefix}-lambda-cloudwatch-logs-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logs_attachment" {
  provider   = aws.us-east-1
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_logs_policy.arn
}