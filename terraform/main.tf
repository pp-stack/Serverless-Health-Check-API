terraform {
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# DynamoDB table for requests
module "dynamodb" {
  source = "./modules/dynamodb"
  env    = var.env
  tags   = { Project = var.project }
}

# Lambda function module
module "lambda" {
  source = "./modules/lambda"
  env    = var.env
  function_name = "${var.env}-health-check-function"
  filename = "${path.module}/../lambda/deployment.zip"
  handler  = "handler.lambda_handler"
  runtime  = "python3.14"
  aws_region = var.aws_region
  table_name = module.dynamodb.table_name
  table_arn  = module.dynamodb.table_arn
  tags = { Project = var.project }
}

# API Gateway module
module "api" {
  source = "./modules/api"
  env = var.env
  function_name = module.lambda.function_name
  function_arn  = module.lambda.function_arn
  aws_region = var.aws_region
  tags = { Project = var.project }
}

output "api_invoke_url" {
  value = module.api.invoke_url
}