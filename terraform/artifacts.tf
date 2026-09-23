resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${var.project_name}-deploy-"

  tags = {
    Name = "${var.project_name}-deployment"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

locals {
  runtime_package = "${path.module}/../dist/wordpress-runtime.tar.gz"
  runtime_sha256  = filesha256(local.runtime_package)
}

resource "aws_s3_object" "runtime" {
  bucket       = aws_s3_bucket.artifacts.id
  key          = "releases/${local.runtime_sha256}/wordpress-runtime.tar.gz"
  source       = local.runtime_package
  source_hash  = local.runtime_sha256
  content_type = "application/gzip"

  depends_on = [
    aws_s3_bucket_versioning.artifacts,
    aws_s3_bucket_server_side_encryption_configuration.artifacts,
    aws_s3_bucket_public_access_block.artifacts,
    aws_s3_bucket_policy.artifacts
  ]
}

resource "aws_iam_role_policy" "download_runtime" {
  name = "${var.project_name}-download-runtime"
  role = aws_iam_role.wordpress.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.artifacts.arn}/releases/*"
      }
    ]
  })
}

output "runtime_package_s3_uri" {
  value = "s3://${aws_s3_bucket.artifacts.id}/${aws_s3_object.runtime.key}"
}

output "runtime_package_sha256" {
  value = local.runtime_sha256
}
