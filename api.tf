######################
#  Lambda
######################

data "aws_iam_policy_document" "metrics_api_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "metrics_api" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:Query"]
    resources = [aws_dynamodb_table.metrics.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses"
    ]
    resources = ["*"]
  }
}



resource "aws_iam_policy" "metrics_api_policy" {
  name   = "metrics_api"
  policy = data.aws_iam_policy_document.metrics_api.json
}

resource "aws_iam_role" "metrics_api_role" {
  name               = "metrics_api"
  assume_role_policy = data.aws_iam_policy_document.metrics_api_assume_role.json
  inline_policy {}
  managed_policy_arns = [
    aws_iam_policy.metrics_api_policy.arn,
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]
}

resource "aws_security_group" "metrics" {
  name   = "metrics_api"
  vpc_id = "vpc-0b06abcc49c87c31f"

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_cloudwatch_log_group" "metrics_api" {
  name              = "/aws/lambda/${aws_lambda_function.metrics_api.id}"
  retention_in_days = 14
}

resource "aws_lambda_function" "metrics_api" {
  function_name    = "metrics_api"
  filename         = data.archive_file.metrics_lambda.output_path
  source_code_hash = data.archive_file.metrics_lambda.output_base64sha256
  handler          = "metrics.api_handler"
  runtime          = "python3.8"
  role             = aws_iam_role.metrics_api_role.arn

  environment {
    variables = {
      DYNAMO_TABLE = aws_dynamodb_table.metrics.name
    }
  }

  vpc_config {
    security_group_ids = [aws_security_group.metrics.id]
    subnet_ids         = ["subnet-08cea9c9b1562577a", "subnet-0610d9d763aa86fad"]
  }

  tags = {
    Name = "bmlt-metrics-api"
  }

  lifecycle {
    ignore_changes = [
      last_modified
    ]
  }
}

######################
#  API Gateway
######################

resource "aws_api_gateway_rest_api" "metrics_api" {
  name        = "metrics_api"
  description = "metrics_api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.metrics_api.id
  parent_id   = aws_api_gateway_rest_api.metrics_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.metrics_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.metrics_api.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.metrics_api.invoke_arn
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.metrics_api.id
  resource_id   = aws_api_gateway_rest_api.metrics_api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.metrics_api.id
  resource_id = aws_api_gateway_method.proxy_root.resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.metrics_api.invoke_arn
}

resource "aws_api_gateway_deployment" "metrics" {
  depends_on = [
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.lambda_root,
  ]

  rest_api_id = aws_api_gateway_rest_api.metrics_api.id
  stage_name  = "testing"
}

resource "aws_lambda_permission" "metrics_api" {
  statement_id  = "AllowMetricsAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.metrics_api.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.metrics_api.execution_arn}/*/*/*"
}

data "aws_route53_zone" "metrics" {
  name = "metrics.bmltenabled.org."
}

resource "aws_acm_certificate" "tz" {
  domain_name       = "api.metrics.bmltenabled.org"
  validation_method = "DNS"
}

resource "aws_route53_record" "metrics_api_validation" {
  for_each = {
    for dvo in aws_acm_certificate.tz.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.metrics.zone_id
}

resource "aws_acm_certificate_validation" "tz" {
  certificate_arn         = aws_acm_certificate.tz.arn
  validation_record_fqdns = [for record in aws_route53_record.metrics_api_validation : record.fqdn]
}

resource "aws_route53_record" "metrics" {
  name    = aws_api_gateway_domain_name.metrics.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.metrics.id

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.metrics.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.metrics.regional_zone_id
  }
}

resource "aws_api_gateway_domain_name" "metrics" {
  regional_certificate_arn = aws_acm_certificate_validation.tz.certificate_arn
  domain_name              = aws_acm_certificate.tz.domain_name

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "metrics" {
  api_id      = aws_api_gateway_rest_api.metrics_api.id
  stage_name  = aws_api_gateway_deployment.metrics.stage_name
  domain_name = aws_api_gateway_domain_name.metrics.domain_name
}
