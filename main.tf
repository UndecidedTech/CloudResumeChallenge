resource "aws_s3_bucket" "site" {
  bucket = var.site_domain
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }
}

locals {
  # Map of file extensions to MIME types
  mime_types = {
    "html" = "text/html"
    "css"  = "text/css"
    "js"   = "application/javascript"
    "png"  = "image/png"
    "jpg"  = "image/jpeg"
    "jpeg" = "image/jpeg"
    "gif"  = "image/gif"
    "ico"  = "image/x-icon"
  }
}

resource "aws_s3_object" "provision_source_files" {
  bucket = aws_s3_bucket.site.id

  for_each = fileset("${var.source_files}/", "**/*.*")

  key          = each.value
  source       = "${var.source_files}/${each.value}"
  content_type = lookup(local.mime_types, element(split(".", basename(each.value)), length(split(".", basename(each.value))) - 1), "application/octet-stream") # Default to binary stream if not found
  etag         = filemd5("${var.source_files}/${each.value}")
}

resource "aws_cloudfront_origin_access_control" "cf-s3-oac" {
  name                              = "CloudFront S3 OAC"
  description                       = "CloudFront S3 OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_acm_certificate" "cert" {
  provider    = aws.us-east-1
  domain      = var.custom_domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

resource "aws_cloudfront_distribution" "cf-dist" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.custom_domain_name]

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.site.id
    origin_access_control_id = aws_cloudfront_origin_access_control.cf-s3-oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.site.id
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
  }

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-cloudfront"
  })
}

data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cf-dist.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static_site_bucket_policy" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

resource "null_resource" "cloudfront_invalidation" {
  # This resource will trigger an invalidation when the S3 objects change
  triggers = {
    # Use a hash of the S3 objects to trigger this resource only when content changes
    s3_object_hash = join("", [for obj in aws_s3_object.provision_source_files : obj.etag])
  }

  # Ensure this runs after the CloudFront distribution is created/updated
  depends_on = [
    aws_cloudfront_distribution.cf-dist,
    aws_s3_object.provision_source_files,
  ]

  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.cf-dist.id} --paths '/*'"
    # Only run this provisioner when the resource is created or updated
    when = create
  }
}


##### BACKEND #####

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
  source_dir  = "./api/src/handlers/bump-count"
  output_path = "./api/src/handlers/lambda_function.zip"
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


