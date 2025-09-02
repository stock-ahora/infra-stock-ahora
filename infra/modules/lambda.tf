module lambda-active-db-service {
  source = "../submodules/lambda/lambda-activation-db-ec2"

  name   = "lambda-activation-ec2-db-true-strock"
  region = "us-east-2"
  ec2_instance_ids = []
  rds_instance_ids = []
  target_tags = {}
}