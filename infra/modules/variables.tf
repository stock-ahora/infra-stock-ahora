variable "project_name" {
  type        = string
  default     = "stock-ahora"
  description = "name of project"
}

variable "tags" {
  type        = string
  default     = "stock"
  description = "Used for naming and tags"
}


variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "aws_profile" {
  type    = string
  default = null
}