
module "ecs" {
  source              = "../submodules/ecs/ecs-go-services"

  region = var.aws_region
  name = var.project_name

  vpc_id = module.vpc.vpc_id
  private_app_subnet_ids = module.vpc.private_app_subnet_ids
  private_app_subnet_cidrs = module.vpc.private_app_subnet_cidrs
  instance_type_od = ["t4g.micro", "t4g.small"]
  instance_type_spot = ["t4g.micro", "t4g.small"]
  ecs_ami_id = ""

  movement_image = "nginx:latest"
  movement_port = 8081

  stock_image = "nginx:latest"
  stock_port = 8082

  client_image = "nginx:latest"
  client_port = 8083

  notification_image = "nginx:latest"
  notification_port = 8084
}