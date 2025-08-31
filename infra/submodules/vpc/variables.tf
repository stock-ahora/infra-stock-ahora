variable "region" {
  type    = string
  default = "us-east-2"
}

# Dos AZ por simplicidad/HA
variable "azs" {
  type    = list(string)
  default = ["us-east-2a", "us-east-2b"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "private_app_subnets" {
  type    = list(string)
  default = ["10.0.32.0/20", "10.0.48.0/20"]
}

variable "private_data_subnets" {
  type    = list(string)
  default = ["10.0.64.0/20", "10.0.80.0/20"]
}

variable "interface_endpoints" {
  description = "Servicios para endpoints interface"
  type        = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
    "ssm",
    "kms",
    "sts"
  ]
}

variable "nat_per_az" {
  type    = bool
  default = true
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "name" {
  type  = string
  default = ""
}