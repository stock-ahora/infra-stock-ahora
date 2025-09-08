variable "sg_app_id" {
  type        = string
  description = "security group id for ecs"
}

variable "sg_db_id" {
  type        = string
  description = "security group id for rds"
}

variable "sg_ecs_id" {
  type        = string
  description = "security group id for ecs tasks"
}

variable "sg_vpn_db" {
    type        = string
    description = "security group id for vpn to rds"
}