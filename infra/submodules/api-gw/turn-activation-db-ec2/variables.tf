variable "name" {
  description = "Prefijo base"
  type        = string
}

variable "region" {
  description = "Región AWS"
  type        = string
}


variable "lambda_arn" {
  description = "arn of lambda"
}

variable "function_name" {
    description = "name of lambda function"
}