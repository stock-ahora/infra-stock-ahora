output "backend_bucket" {
  value = aws_s3_bucket.tf_state.bucket
}

output "backend_table" {
  value = aws_dynamodb_table.tf_lock.name
}