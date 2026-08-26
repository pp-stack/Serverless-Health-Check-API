provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = var.tags
}

resource "aws_dynamodb_table" "state_lock" {
  name         = var.state_lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "state_lock_table" {
  value = aws_dynamodb_table.state_lock.name
}
