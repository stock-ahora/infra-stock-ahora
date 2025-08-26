variable "name" {
  type = string
  description = "name of api"

}

variable "dns_name" {
  type = string
  description = "dns name of applications"
}

variable "aws_lb_nlb_arn" {
  type = string
}

variable "api_ports" {
  type = map(number)
  default = {
    movement     = 8081
    stock        = 8082
    client       = 8083
    notification = 8084
  }
}

variable "region" {
  type = string
  description = "region"
}