data "aws_caller_identity" "current" {}

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.env}-health-check-api"
  description = "Health check API for ${var.env}"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  tags = var.tags
}

resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "health"
}

# Model and validator for POST requests to ensure 'payload' exists
resource "aws_api_gateway_model" "post_model" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  name        = "PostPayloadModel"
  content_type = "application/json"
  schema = jsonencode({
    type = "object",
    required = ["payload"],
    properties = {
      payload = { type = "string" }
    }
  })
}

resource "aws_api_gateway_request_validator" "body_validator" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  name        = "BodyValidator"
  validate_request_body = true
}

resource "aws_api_gateway_method" "post_health" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "POST"
  authorization = "NONE"
  request_models = {
    "application/json" = aws_api_gateway_model.post_model.name
  }
  request_validator_id = aws_api_gateway_request_validator.body_validator.id
}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.health.id
  http_method = aws_api_gateway_method.post_health.http_method
  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri  = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.function_arn}/invocations"
}

# Allow API Gateway to invoke the Lambda
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke${var.env}"
  action        = "lambda:InvokeFunction"
  function_name = var.function_name
  principal     = "apigateway.amazonaws.com"
  # Restrict source to this API execution ARN
  source_arn = "${aws_api_gateway_rest_api.this.execution_arn}/*/*/health"
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_integration.post_integration]
  rest_api_id = aws_api_gateway_rest_api.this.id
}

# Stage resource so we can apply settings
resource "aws_api_gateway_stage" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name = var.env

  tags = var.tags
}

# Throttling settings applied to stage methods
resource "aws_api_gateway_method_settings" "throttle" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name

  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level = "INFO"
    data_trace_enabled = false
    throttling_rate_limit = 50
    throttling_burst_limit = 100
  }
}

output "invoke_url" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${var.aws_region}.amazonaws.com/${var.env}/health"
}
