terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "infra-true-stock-tfstate-408ca114"
    key            = "infra/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "infra-true-stock-tf-lock"
    encrypt        = false
  }



  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

