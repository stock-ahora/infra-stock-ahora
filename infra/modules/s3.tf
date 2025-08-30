module "s3-static-site" {
  source      = "../submodules/s3/s3-static-site"
  bucket_name = "${var.project_name}-site"


}
module "s3-docs" {
  source = "../submodules/s3/s3-docs"

  bucket_name = "true-stock-docs"
}