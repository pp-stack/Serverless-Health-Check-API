data "aws_caller_identity" "current" {}

resource "aws_iam_role" "lambda" {
  name = "${var.env}-health-check-lambda-role"
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
  tags = var.tags
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.env}-health-check-lambda-policy"
  role = aws_iam_role.lambda.id

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
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.function_name}:*"
      },
      {
        Action = [
          "dynamodb:PutItem"
        ],
        Effect   = "Allow",
        Resource = var.table_arn
      },
      {
        # X-Ray trace write actions have no resource-level ARNs to scope by -
        # this is the one mandatory wildcard the AWS X-Ray IAM model allows.
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  # checkov:skip=CKV_AWS_158: customer-managed KMS key - optional bonus item
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 400
  tags              = var.tags
}

resource "aws_lambda_function" "this" {
  # checkov:skip=CKV_AWS_173: customer-managed KMS key - optional bonus item
  # checkov:skip=CKV_AWS_117: Lambda in its own VPC - optional bonus item
  # checkov:skip=CKV_AWS_116: this Lambda is only ever invoked synchronously
  # via API Gateway proxy integration, where a failure returns straight to
  # the caller - a DLQ (for failed async invocations) has nothing to catch
  # here.
  # checkov:skip=CKV_AWS_272: code-signing needs a signing profile and a
  # publishing pipeline step, disproportionate infrastructure for this
  # exercise.
  # checkov:skip=CKV_AWS_115: a reserved concurrency limit is an operational
  # capacity choice, not a security control, and would just add another way
  # for this simple health check to start throttling itself.
  filename         = var.filename
  function_name    = var.function_name
  handler          = var.handler
  runtime          = var.runtime
  role             = aws_iam_role.lambda.arn
  source_code_hash = filebase64sha256(var.filename)

  environment {
    variables = {
      REQUESTS_TABLE = var.table_name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda,
  ]
}
