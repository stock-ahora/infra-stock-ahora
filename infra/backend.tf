terraform {
  backend "s3" {
    bucket         = "infra-stock-ahora-tfstate-c6058f0d"
    key            = "infra/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "infra-stock-ahora-tf-lock"
    encrypt        = false
  }
}