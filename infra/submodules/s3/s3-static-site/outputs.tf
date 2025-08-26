output "bucket_id" {
  description = "Bucket name (id) for the static site"
  value       = aws_s3_bucket.site.id
}

output "bucket_name" {
  description = "Bucket name"
  value       = aws_s3_bucket.site.bucket
}

output "bucket_arn" {
  description = "Bucket ARN"
  value       = aws_s3_bucket.site.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name used by CloudFront origin"
  value       = aws_s3_bucket.site.bucket_regional_domain_name
}
