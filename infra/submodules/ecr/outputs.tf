output "ecr_repo_urls" {
  description = "URLs de los repos ECR por servicio"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "ecr_repo_arns" {
  value = { for k, v in aws_ecr_repository.this : k => v.arn }
}