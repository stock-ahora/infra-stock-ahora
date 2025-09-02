module "client-api" {
  source = "../submodules/api-gw/client"
  name   = "client-api"
  aws_lb_nlb_arn = module.ecs.aws_lb_nlb_arn
  api_ports = {
    movement     = 8081
    stock        = 8082
    client       = 8083
    notification = 8084
  }
  dns_name = module.ecs.dns_name
  region   = var.aws_region

  depends_on = [module.ecs]
}

module "turn-activation-db-ec2" {
  source = "../submodules/api-gw/turn-activation-db-ec2"
  name   = "turn-activation-db-ec2"
  region = var.aws_region
  lambda_arn = module.lambda-active-db-service.lambda_invoke_arn
  function_name = module.lambda-active-db-service.lambda_name

  depends_on = [module.lambda-active-db-service]
}