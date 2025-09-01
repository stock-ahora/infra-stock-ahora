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
