# =============================================================================
# AWS Cloud Portfolio - Real-Time Data Lakehouse Pipeline
# Terraform Configuration - S3 Data Lake Foundation
# =============================================================================
# This file defines the core S3 infrastructure for your data lakehouse.
# Usage:
#   1. Install Terraform: https://developer.hashicorp.com/terraform/install
#   2. Run: terraform init
#   3. Run: terraform plan        (preview what will be created)
#   4. Run: terraform apply       (create the resources)
#   5. Run: terraform destroy     (tear down when done to avoid charges)
# =============================================================================

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1" # Mumbai - closest to Hyderabad
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "aws-cloud-portfolio"
}

variable "environment" {
  description = "Environment tag (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Random suffix to ensure globally unique bucket names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  bucket_prefix = "${var.project_name}-${var.environment}"
  bucket_suffix = random_id.bucket_suffix.hex
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket: Raw Data Layer
# Purpose: Landing zone for raw JSON data from Kinesis/API ingestion
# Data is partitioned by: year/month/day/hour
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "raw" {
  bucket = "${local.bucket_prefix}-raw-${local.bucket_suffix}"
  tags   = merge(local.common_tags, { Layer = "raw" })
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3 encryption at rest
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule: Move raw data to cheaper storage after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "archive-old-raw-data"
    status = "Enabled"

    filter {} # Apply to all objects in the bucket

    transition {
      days          = 90
      storage_class = "STANDARD_IA" # Infrequent Access - cheaper for old data
    }

    transition {
      days          = 180
      storage_class = "GLACIER" # Very cheap long-term storage
    }
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket: Processed Data Layer
# Purpose: Cleaned Parquet files output by AWS Glue ETL jobs
# This is what Athena and Redshift will query
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "processed" {
  bucket = "${local.bucket_prefix}-processed-${local.bucket_suffix}"
  tags   = merge(local.common_tags, { Layer = "processed" })
}

resource "aws_s3_bucket_versioning" "processed" {
  bucket = aws_s3_bucket.processed.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket                  = aws_s3_bucket.processed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# S3 Bucket: Archive Layer
# Purpose: Long-term storage for historical/backup data
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "archive" {
  bucket = "${local.bucket_prefix}-archive-${local.bucket_suffix}"
  tags   = merge(local.common_tags, { Layer = "archive" })
}

resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket                  = aws_s3_bucket.archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Archive bucket uses Glacier by default for cost savings
resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    id     = "move-to-glacier"
    status = "Enabled"

    filter {} # Apply to all objects in the bucket

    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
}

# -----------------------------------------------------------------------------
# Outputs
# Display key information after terraform apply
# -----------------------------------------------------------------------------
output "raw_bucket_name" {
  description = "S3 bucket for raw ingested data"
  value       = aws_s3_bucket.raw.bucket
}

output "processed_bucket_name" {
  description = "S3 bucket for processed Parquet data"
  value       = aws_s3_bucket.processed.bucket
}

output "archive_bucket_name" {
  description = "S3 bucket for archived data"
  value       = aws_s3_bucket.archive.bucket
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}
