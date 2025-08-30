module "aim-ecr" {
  source = "../submodules/aim"


  ecr_repo_arns = module.ecr.ecr_repo_arns
}

module "task_app" {
  source = "../submodules/aim/aim-go-text-extract"
  arn-docs = module.s3-docs.arn-docs
  bucket_name = module.s3-docs.bucket-name
  name = "task_app"
}