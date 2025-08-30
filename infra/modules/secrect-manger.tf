module "secret-app" {
  source = "../submodules/secret-manager/secret-app"

  name     = "secret-app"
  task_app_name = module.task_app.task_app_name
}