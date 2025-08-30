module "ecr"{
  source = "../submodules/ecr"

  ecr_repositories = ["api-movement", "api-stock", "api-client", "api-notification"]
  kms_key_arn = ""
  project_name = var.project_name

}