
output "secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}