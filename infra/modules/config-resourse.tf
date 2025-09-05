module "config-sg-ecs-rds" {
  source = "../submodules/config/config-sg-ecs-rds"

  sg_app_id = module.vpc.sg_app_id
  sg_db_id  = module.db-main.sg_db_id
  sg_ecs_id = module.ecs.sg_app_id
}