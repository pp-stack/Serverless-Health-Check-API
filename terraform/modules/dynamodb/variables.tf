variable "env" {
  description = "Environment short name, e.g. staging or prod"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "Optional KMS Key ARN for customer-managed encryption"
  type        = string
  default     = ""
}
