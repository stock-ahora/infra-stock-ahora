module "cloudfront-static-site"{
  source = "../submodules/cloudfront/cloudfront-static-site"

  bucket_regional_domain_name   = module.s3-static-site.bucket_regional_domain_name
  bucket_name                   = module.s3-static-site.bucket_name
  bucket_id                     = module.s3-static-site.bucket_id
}
