variable "env" {
  description = "Environment short name, e.g. staging or prod"
  type        = string
}

variable "function_name" {
  description = "Lambda function name to integrate"
  type        = string
}

variable "function_arn" {
  description = "Lambda function ARN to integrate"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
