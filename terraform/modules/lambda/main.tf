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
        Effect = "Allow",
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.function_name}:*"
      },
      {
        Action = [
          "dynamodb:PutItem"
        ],
        Effect = "Allow",
        Resource = var.table_arn
      }
    ]
  })
}

resource "aws_lambda_function" "this" {
  filename         = var.filename
  function_name    = var.function_name
  handler          = var.handler
  runtime          = var.runtime
  role             = aws_iam_role.lambda.arn

  environment {
    variables = {
      REQUESTS_TABLE = var.table_name
    }
  }

  tags = var.tags
}
