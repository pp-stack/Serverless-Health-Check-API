variable "aws_region" {
  description = "AWS region for bootstrap resources"
  type        = string
  default     = "eu-west-1"
}

variable "env" {
  description = "Environment (staging/prod)"
  type        = string
}

variable "project" {
  description = "Project name used in resource naming"
  type        = string
  default     = "health-check"
}

variable "state_bucket_name" {
  description = "S3 bucket name to store Terraform state (must be globally unique)"
  type        = string
}

variable "state_lock_table" {
  description = "DynamoDB table name to use for Terraform state locking"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
