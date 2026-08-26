# Model vault. Three prefixes:
#   audit/     every request LiteLLM handles (s3 callback)
#   prompts/   versioned prompt templates
#   artifacts/ model manifests, eval results
resource "aws_s3_bucket" "vault" {
  bucket = "${local.name_prefix}-model-vault"

  depends_on = [null_resource.localstack_ready]
}

resource "aws_s3_bucket_versioning" "vault" {
  bucket = aws_s3_bucket.vault.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault" {
  bucket = aws_s3_bucket.vault.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vault" {
  bucket = aws_s3_bucket.vault.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Prompt logs grow fastest and nobody prunes them. Expire by default.
resource "aws_s3_bucket_lifecycle_configuration" "vault" {
  bucket = aws_s3_bucket.vault.id

  rule {
    id     = "expire-audit-logs"
    status = "Enabled"

    filter {
      prefix = "audit/"
    }

    expiration {
      days = var.audit_log_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.vault]
}
