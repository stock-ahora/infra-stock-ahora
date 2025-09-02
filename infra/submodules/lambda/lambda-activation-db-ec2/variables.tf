variable "name" {
  description = "Prefijo base"
  type        = string
}

variable "region" {
  description = "Región AWS"
  type        = string
}

variable "ec2_instance_ids" {
  type = list(string)
}

variable "rds_instance_ids" {
  type = list(string)
}

variable "target_tags"      {
  type = map(string)
}
