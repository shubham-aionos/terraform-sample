
resource "aws_s3_bucket" "terraform_state" {
  #checkov:skip=CKV2_AWS_62:Event notifications are unnecessary for the Terraform state bucket
  #checkov:skip=CKV_AWS_18:S3 access logging is deferred for this disposable cost-conscious lab
  #checkov:skip=CKV_AWS_144:Cross-region replication is unnecessary for this disposable single-region lab
  #checkov:skip=CKV_AWS_145:SSE-S3 encryption is sufficient for this disposable lab; customer-managed KMS is deferred
  bucket        = "three-tier-terraform-state-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "three-tier-terraform-state"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
