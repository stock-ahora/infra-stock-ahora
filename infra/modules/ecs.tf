
module "ecs" {
  source = "../submodules/ecs/ecs-go-services"

  region = var.aws_region
  name   = var.project_name

  vpc_id                   = module.vpc.vpc_id
  private_app_subnet_ids   = module.vpc.private_app_subnet_ids
  private_app_subnet_cidrs = module.vpc.private_app_subnet_cidrs
  instance_type_od         = ["t4g.small", "t4g.medium"]
  instance_type_spot       = ["t4g.small", "t4g.medium"]
  ecs_ami_id               = ""

  movement_image = "859551916894.dkr.ecr.us-east-2.amazonaws.com/true-stock/api-movement:test-arm"
  movement_port  = 8081

  stock_image = "859551916894.dkr.ecr.us-east-2.amazonaws.com/true-stock/api-stock:test-arm-test-secret-manager6"
  stock_port  = 8082

  client_image = "859551916894.dkr.ecr.us-east-2.amazonaws.com/true-stock/api-client:test-arm"
  client_port  = 8083

  notification_image = "859551916894.dkr.ecr.us-east-2.amazonaws.com/true-stock/api-notification:test-arm"
  notification_port  = 8084
  task_app_arn       = module.task_app.task_app_arn

  depends_on = [module.vpc, module.task_app]
  sg_app_id = module.vpc.sg_app_id
}
