terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    # <<< Reemplaza con los outputs de bootstrap: bucket y dynamodb_table >>>
    bucket         = "REPLACE_ME_BUCKET"
    key            = "infra/terraform.tfstate"
    region         = "REPLACE_ME_REGION"
    dynamodb_table = "REPLACE_ME_TABLE"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}