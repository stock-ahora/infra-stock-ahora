variable "project_name" {
  description = "Short name for tags and backend resources"
  type        = string
  default     = "infra-stock-ahora"
}

variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "aws_profile" {
  type    = string
  default = null
}