variable "project_name" {
  type        = string
  default     = "ecs-free-tier-demo"
  description = "Used for naming and tags"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type    = string
  default = null
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "instance_type" {
  type    = string
  default = "t4g.micro" # free-tier elegible (ARM/Graviton)
}

variable "app_image" {
  type        = string
  default     = "public.ecr.aws/nginx/nginx:latest"
  description = "Container image to run initially"
}

variable "app_container_name" {
  type    = string
  default = "app"
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "allow_cidr_ingress" {
  type    = string
  default = "0.0.0.0/0"
  description = "CIDR allowed to reach the service ports"
}