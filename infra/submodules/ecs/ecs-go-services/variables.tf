variable "region"  {
  type = string
  default = "us-east-2"
}
variable "name"    {
  type = string
  default = "stockahora"
}

variable "vpc_id"  {
  type = string
}

variable "sg_app_id" {
  type = string
}

# Subredes privadas donde correr ECS y donde vive el NLB
variable "private_app_subnet_ids"   {
  type = list(string)
}

# CIDR(s) de esas subredes (para SG de ECS)
variable "private_app_subnet_cidrs" {
  type = list(string)
}

# AMI opcional (si vacio, se usa la recomendada por SSM)
variable "ecs_ami_id" {
  type = string
  default = ""
}

variable "instance_type_spot" {
  description = "Tipos ARM64 para Spot (mismo arq que la AMI)"
  type        = list(string)
  default     = ["t4g.micro", "t4g.small"]  # agrega más si quieres
}

# (opcional) para On-Demand:
variable "instance_type_od" {
  type    = list(string)
  default = ["t4g.micro", "t4g.small"]
}

# Imágenes y puertos
variable "movement_image"     {
  type = string
  default = "nginx:latest"
}
variable "movement_port"      {
  type = number
  default = 8081
}

variable "stock_image"        {
  type = string
  default = "nginx:latest"
}

variable "stock_port"         {
  type = number
  default = 8082
}

variable "client_image"       {
  type = string
  default = "nginx:latest"
}
variable "client_port"        {
  type = number
  default = 8083
}

variable "notification_image" {
  type = string
  default = "nginx:latest"
}
variable "notification_port"  {
  type = number
  default = 8084
}

variable "task_app_arn" {
  type = string
  description = "arn of rol for s3 and textExtract"
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
    "sts",
    "ecs",          # si quieres que ECS Agent hable por endpoint
    "ecs-agent",
    "ecs-telemetry"
  ]
}