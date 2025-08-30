
module "vpc" {
  source = "../submodules/vpc"
  name = var.project_name

  # deja la VPC como ya está creada:
  vpc_cidr = "10.20.0.0/16"

  # misma región/AZs que estás usando
  azs = ["us-east-2a", "us-east-2b"]

  # <<< CAMBIO CLAVE: usa 10.20.x.x, no 10.0.x.x >>>
  public_subnets       = ["10.20.0.0/20", "10.20.16.0/20"]
  private_app_subnets  = ["10.20.32.0/20", "10.20.48.0/20"]
  private_data_subnets = ["10.20.64.0/20", "10.20.80.0/20"]

  interface_endpoints = ["ecr.api", "ecr.dkr", "logs", "secretsmanager", "ssm", "kms", "sts"]
  nat_per_az          = true
  app_port            = 8080
  db_port             = 5432
}
