locals {
  tags = {
    Project = var.project_name
  }
}

module "vpc" {
  source               = "./modules/vpc"
  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  tags                 = local.tags
}

module "ecs" {
  source              = "./modules/ecs"
  project_name        = var.project_name
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  instance_type       = var.instance_type
  app_image           = var.app_image
  app_container_name  = var.app_container_name
  app_port            = var.app_port
  desired_count       = var.desired_count
  allow_cidr_ingress  = var.allow_cidr_ingress
  tags                = local.tags
}

output "public_instance_ip" {
  value = module.ecs.instance_public_ip
}

output "service_url_hint" {
  value = "http://${module.ecs.instance_public_ip}:${var.app_port}/"
}