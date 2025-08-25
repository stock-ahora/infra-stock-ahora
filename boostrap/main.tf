  terraform {
    required_version = ">= 1.5.0"
  }

  provider "aws" {
    region  = var.aws_region
    profile = var.aws_profile
  }

  resource "random_id" "suffix" {
    byte_length = 4
  }

  resource "aws_s3_bucket" "tf_state" {
    bucket = "${var.project_name}-tfstate-${random_id.suffix.hex}"
    force_destroy = true

    tags = {
      Project = var.project_name
      Purpose = "terraform-backend"
    }
  }


  resource "aws_dynamodb_table" "tf_lock" {
    name         = "${var.project_name}-tf-lock"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "LockID"

    attribute {
      name = "LockID"
      type = "S"
    }

    tags = {
      Project = var.project_name
      Purpose = "terraform-backend-lock"
    }


  }

  output "backend_bucket" {
    value = aws_s3_bucket.tf_state.bucket
  }

  output "backend_table" {
    value = aws_dynamodb_table.tf_lock.name
  }