
//module "ecs" {
//  source              = "./modules/ecs"
//  project_name        = var.project_name
//  vpc_id              = module.vpc.vpc_id
//  public_subnet_ids   = module.vpc.public_subnet_ids
//  instance_type       = var.instance_type
//  app_image           = var.app_image
//  app_container_name  = var.app_container_name
//  app_port            = var.app_port
//  desired_count       = var.desired_count
//  allow_cidr_ingress  = var.allow_cidr_ingress
//  tags                = var.tags
//}