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

variable "github_org" {
  description = "GitHub organization or user that owns the repository (used in the OIDC trust condition)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (used in the OIDC trust condition)"
  type        = string
}

variable "manage_oidc_provider" {
  description = "Whether this bootstrap should create the account's GitHub OIDC provider. Set to false in a second environment sharing the same AWS account so the provider (an account-level singleton) is only created once."
  type        = bool
  default     = true
}
