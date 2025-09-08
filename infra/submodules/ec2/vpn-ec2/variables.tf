variable "aws_vpc_id" {
  type        = string
  description = "VPC ID donde se lanzará la instancia EC2"
}

variable "project_name" {
  type = string
}
variable "region"       {
  type = string
  default = "us-east-2"
}

variable "public_subnet_ids" {
    type = list(string)
    description = "Lista de IDs de subredes públicas en la VPC"
}
# Usa una key existente en tu cuenta para SSH. Si prefieres SSM y NO abrir SSH, puedes omitir esto y cerrar el 22/TCP.
variable "ssh_key_name" {
  type = string
  default = null
}
# Restringe SSH a tu IP (solo si vas a abrir 22/TCP)
variable "ssh_cidr"     {
  type = string
  default = "186.189.90.236/32"
}

data "aws_ami" "ubuntu_jammy" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }

}
