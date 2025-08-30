module "db-main" {
  source = "../submodules/rds-aurora/db-main"

  db_password = "9W=?Wr2-008vS?>"
  db_username = "db_user"
  region = var.aws_region
  vpc_id      = module.vpc.vpc_id
  //db_subnets  = module.vpc.private_data_subnet_ids
  db_subnets  = module.vpc.public_subnet_ids
  name        = "${var.project_name}-aurora-cluster"
  allowed_ips = ["186.189.90.100/32"]
}