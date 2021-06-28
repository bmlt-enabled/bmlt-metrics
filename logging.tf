######################
#  Lambda
######################

data "archive_file" "metrics_lambda" {
  type        = "zip"
  source_file = "${path.module}/metrics.py"
  output_path = "${path.module}/metrics.zip"
}

resource "aws_cloudwatch_log_group" "metrics" {
  name              = "/aws/lambda/${aws_lambda_function.metrics_logger.id}"
  retention_in_days = 14
}

resource "aws_lambda_function" "metrics_logger" {
  function_name                  = "metrics_logger"
  filename                       = data.archive_file.metrics_lambda.output_path
  handler                        = "metrics.logger_handler"
  role                           = aws_iam_role.metrics_logger.arn
  reserved_concurrent_executions = 1
  source_code_hash               = data.archive_file.metrics_lambda.output_base64sha256
  runtime                        = "python3.8"
  timeout                        = 30

  environment {
    variables = {
      DYNAMO_TABLE = aws_dynamodb_table.metrics.name
    }
  }

  tags = {
    Name = "bmlt-metrics-logging"
  }

  vpc_config {
    security_group_ids = [aws_security_group.metrics.id]
    subnet_ids         = ["subnet-08cea9c9b1562577a", "subnet-0610d9d763aa86fad"]
  }

  lifecycle {
    ignore_changes = [
      last_modified
    ]
  }
}

resource "aws_lambda_permission" "bmlt_metrics_cloudwatch" {
  statement_id  = "bmlt-metrics-cloudwatch-permission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.metrics_logger.arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.bmlt_metrics.arn
}

data "aws_iam_policy_document" "metrics_logger_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "metrics_logger" {
  name               = "metrics-logger"
  description        = "For metrics logger Lambda"
  assume_role_policy = data.aws_iam_policy_document.metrics_logger_assume_role.json
  tags = {
    Name = "bmlt-metrics"
  }
}

resource "aws_iam_policy" "metrics_logger_policy" {
  name   = "metrics-logger-lambda-role"
  policy = data.aws_iam_policy_document.metrics_logger_policy.json
}

resource "aws_iam_role_policy_attachment" "metrics_logger_policy_attachment" {
  role       = aws_iam_role.metrics_logger.name
  policy_arn = aws_iam_policy.metrics_logger_policy.arn
}

data "aws_iam_policy_document" "metrics_logger_policy" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.metrics.arn}:*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["DynamoDB:PutItem"]
    resources = [aws_dynamodb_table.metrics.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses"
    ]
    resources = ["*"]
  }
}

######################
#  Dynamo
######################

resource "aws_dynamodb_table" "metrics" {
  name           = "metrics-logger"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "date"

  attribute {
    name = "date"
    type = "S"
  }

  tags = {
    Name = "bmlt-metrics"
  }
}

######################
#  Cloudwatch
######################

resource "aws_cloudwatch_event_rule" "bmlt_metrics" {
  name                = "bmlt-metrics-lambda"
  description         = "bmlt-metrics-lambda-daily-12-am"
  schedule_expression = "cron(0 0 ? * * *)"
}

resource "aws_cloudwatch_event_target" "bmlt_metrics_target" {
  target_id = "bmlt-metrics-lambda-target"
  rule      = aws_cloudwatch_event_rule.bmlt_metrics.name
  arn       = aws_lambda_function.metrics_logger.arn
}
