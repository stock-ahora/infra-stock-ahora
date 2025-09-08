module "ec2-rabbitMQ" {
  source = "../submodules/ec2/reabbitmq"


  allowed_admin_ips = ["186.189.90.236/32"]
  ebs_size_gb       = 20
  instance_type     = "t3.micro"
  name              = "${var.project_name}-rabbit-mq"
  region            = var.aws_region
  //sg_app_id         = module.ecs.sg_app_id
  sg_app_id         = ""
  subnet_id_private = module.vpc.private_app_subnet_ids[0]
  vpc_id            = module.vpc.vpc_id

  depends_on = [module.vpc]

}

module "vpn-ec2" {
    source = "../submodules/ec2/vpn-ec2"

   aws_vpc_id = module.vpc.vpc_id
  project_name = "vpn"
  public_subnet_ids = module.vpc.public_subnet_ids
}