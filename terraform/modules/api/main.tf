data "aws_caller_identity" "current" {}

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.env}-health-check-api"
  description = "Health check API for ${var.env}"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "health"
}

# Model and validator for POST requests to ensure 'payload' exists.
# Type is intentionally left unconstrained: only presence of the key is
# enforced here, mirroring the Lambda's own validation.
resource "aws_api_gateway_model" "post_model" {
  rest_api_id  = aws_api_gateway_rest_api.this.id
  name         = "PostPayloadModel"
  content_type = "application/json"
  schema = jsonencode({
    type     = "object",
    required = ["payload"]
  })
}

resource "aws_api_gateway_request_validator" "body_validator" {
  rest_api_id           = aws_api_gateway_rest_api.this.id
  name                  = "BodyValidator"
  validate_request_body = true
}

resource "aws_api_gateway_method" "post_health" {
  # checkov:skip=CKV_AWS_59: API-key auth - optional bonus item
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
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.health.id
  http_method             = aws_api_gateway_method.post_health.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.function_arn}/invocations"
}

# GET /health - no body, so no request validator is attached
resource "aws_api_gateway_method" "get_health" {
  # checkov:skip=CKV_AWS_59: API-key auth - optional bonus item
  # checkov:skip=CKV2_AWS_53: GET has no request body to validate - the
  # required 'payload' key check applies only to POST, which does have a
  # validator attached.
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.health.id
  http_method             = aws_api_gateway_method.get_health.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.function_arn}/invocations"
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
  depends_on = [
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.get_integration,
  ]
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.health.id,
      aws_api_gateway_method.post_health.id,
      aws_api_gateway_integration.post_integration.id,
      aws_api_gateway_method.get_health.id,
      aws_api_gateway_integration.get_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Stage resource so we can apply settings
resource "aws_api_gateway_stage" "this" {
  # checkov:skip=CKV_AWS_76: the account-level CloudWatch role this needs
  # (terraform/bootstrap's aws_api_gateway_account) is now managed, but
  # access_log_settings itself (a log group + format) isn't wired up here -
  # not implemented for this exercise's scope.
  # checkov:skip=CKV_AWS_120: response caching is wrong for a liveness check -
  # it would make /health report stale results instead of the current state.
  # checkov:skip=CKV2_AWS_29: WAFv2 web ACL - optional bonus item
  # checkov:skip=CKV2_AWS_51: client-certificate auth - optional bonus item
  # checkov:skip=CKV_AWS_73: X-Ray tracing here needed a service-linked role
  # this AWS account couldn't grant through any IAM scoping tried; disabled
  # rather than keep guessing - see terraform/bootstrap/main.tf history.
  # Lambda's own X-Ray tracing is unaffected.
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.env

  tags = var.tags
}

# Throttling settings applied to stage methods
resource "aws_api_gateway_method_settings" "throttle" {
  # checkov:skip=CKV_AWS_225: response caching is wrong for a liveness check -
  # it would make /health report stale results instead of the current state.
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name

  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "INFO"
    data_trace_enabled     = false
    throttling_rate_limit  = 50
    throttling_burst_limit = 100
  }
}

output "invoke_url" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${var.aws_region}.amazonaws.com/${var.env}/health"
}
