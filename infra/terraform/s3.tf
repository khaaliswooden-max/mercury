# s3.tf — buckets for AFI artifacts and CodeBuild logs.
#
# afi_artifacts: holds the DCP tarballs that aws_build_dcp_from_cl.sh
#                produces and that `aws ec2 create-fpga-image` consumes.
# afi_logs:      CodeBuild and AFI registration logs.
#
# Both buckets enable versioning so a bad build doesn't overwrite a known-
# good one, and SSE-S3 encryption for compliance hygiene.

resource "aws_s3_bucket" "afi_artifacts" {
  bucket = local.artifacts_bucket_name
}

resource "aws_s3_bucket_versioning" "afi_artifacts" {
  bucket = aws_s3_bucket.afi_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "afi_artifacts" {
  bucket = aws_s3_bucket.afi_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "afi_artifacts" {
  bucket = aws_s3_bucket.afi_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "afi_logs" {
  bucket = local.logs_bucket_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "afi_logs" {
  bucket = aws_s3_bucket.afi_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "afi_logs" {
  bucket = aws_s3_bucket.afi_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: AFI logs aren't useful past 90 days. AFI artifacts are kept
# indefinitely; rely on versioning + manual cleanup for those.
resource "aws_s3_bucket_lifecycle_configuration" "afi_logs" {
  bucket = aws_s3_bucket.afi_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}
