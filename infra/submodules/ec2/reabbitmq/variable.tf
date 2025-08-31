variable "name"                {
  type = string
}

variable "vpc_id"              {
  type = string
}

variable "subnet_id_private"   {
  type = string
}

variable "sg_app_id"           {
  type = string
}

variable "allowed_admin_ips"   {
  type = list(string)
}
variable "region"              {
  type = string
}

variable "instance_type"       {
  type = string
}

variable "ebs_size_gb"         {
  type = number
}
