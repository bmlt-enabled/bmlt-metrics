######################
#  IAM
######################

data "aws_iam_policy_document" "metrics_api_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "metrics_api" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:Scan"]
    resources = [aws_dynamodb_table.metrics.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
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
  ]
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

resource "aws_api_gateway_resource" "metrics" {
  rest_api_id = aws_api_gateway_rest_api.metrics_api.id
  parent_id   = aws_api_gateway_rest_api.metrics_api.root_resource_id
  path_part   = "metrics"
}

resource "aws_api_gateway_method" "metrics_get" {
  rest_api_id   = aws_api_gateway_rest_api.metrics_api.id
  resource_id   = aws_api_gateway_resource.metrics.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.querystring.start_date" = true,
    "method.request.querystring.end_date"   = true,
  }
}

resource "aws_api_gateway_request_validator" "metrics_get" {
  name                        = "metrics-api-metrics-get"
  rest_api_id                 = aws_api_gateway_rest_api.metrics_api.id
  validate_request_body       = true
  validate_request_parameters = true
}

resource "aws_api_gateway_integration" "metrics_get" {
  rest_api_id             = aws_api_gateway_rest_api.metrics_api.id
  resource_id             = aws_api_gateway_resource.metrics.id
  http_method             = aws_api_gateway_method.metrics_get.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:us-east-1:dynamodb:action/Scan"
  credentials             = aws_iam_role.metrics_api_role.arn
  passthrough_behavior    = "WHEN_NO_TEMPLATES"
  request_templates = {
    "application/json" = jsonencode({
      TableName        = aws_dynamodb_table.metrics.name
      FilterExpression = "#d BETWEEN :v1 AND :v2"
      ExpressionAttributeValues = {
        ":v1" = {
          S = "$input.params('start_date')"
        }
        ":v2" = {
          S = "$input.params('end_date')"
        }
      }
      ExpressionAttributeNames = {
        "#d" = "date"
      }
    })
  }
}

resource "aws_api_gateway_method_response" "metrics_get_200" {
  rest_api_id = aws_api_gateway_rest_api.metrics_api.id
  resource_id = aws_api_gateway_resource.metrics.id
  http_method = aws_api_gateway_method.metrics_get.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "metrics_get" {
  rest_api_id = aws_api_gateway_rest_api.metrics_api.id
  resource_id = aws_api_gateway_resource.metrics.id
  http_method = aws_api_gateway_method.metrics_get.http_method
  status_code = aws_api_gateway_method_response.metrics_get_200.status_code

  # Transforms the backend JSON response to XML
  response_templates = {
    "application/json" = <<EOF
#set($inputRoot = $input.path('$'))
[
#foreach($elem in $inputRoot.Items)
    {
        "date": "$elem.date.S",
        "num_zones": "$elem.num_zones.S",
        "num_regions": "$elem.num_regions.S",
        "num_areas": "$elem.num_areas.S",
        "num_groups": "$elem.num_groups.S",
        "num_meetings": "$elem.num_meetings.S"
    }#if($foreach.hasNext),
#end
#end

]
EOF
  }
}

resource "aws_api_gateway_deployment" "metrics" {
  depends_on = [
    aws_api_gateway_integration.metrics_get,
    aws_api_gateway_integration_response.metrics_get,
  ]

  rest_api_id = aws_api_gateway_rest_api.metrics_api.id
  stage_name  = "testing"
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
