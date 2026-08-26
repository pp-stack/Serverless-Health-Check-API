variable "env" {
  description = "Environment short name, e.g. staging or prod"
  type        = string
}

variable "function_name" {
  description = "Name for the Lambda function"
  type        = string
}

variable "filename" {
  description = "Path to the deployment package zip file"
  type        = string
}

variable "handler" {
  description = "Lambda handler (e.g. handler.lambda_handler)"
  type        = string
}

variable "runtime" {
  description = "Lambda runtime (e.g. python3.9)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "table_name" {
  description = "DynamoDB table name to write to"
  type        = string
}

variable "table_arn" {
  description = "DynamoDB table ARN for IAM policy scoping"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
