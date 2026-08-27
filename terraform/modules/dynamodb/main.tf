resource "aws_dynamodb_table" "this" {
  name         = "${var.env}-requests-db"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # checkov:skip=CKV_AWS_119: customer-managed KMS key is an optional
  server_side_encryption {
    enabled = true
    # kms_key_arn = var.kms_key_arn # optional customer-managed key
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = var.tags
}
