variable "vpc_id" {
  type = string
}

variable "db_subnets" {
  type = list(string) # IDs de subredes privadas para la DB
}

variable "db_username" {
  type    = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "region" {
  type    = string
}

variable "name" {
}

variable "allowed_ips" {
  type = list(string)
  description = "Lista de IPs permitidas para acceder al RDS en formato CIDR"
}