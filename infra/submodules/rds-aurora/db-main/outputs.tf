output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "rds_port" {
  value = aws_db_instance.postgres.port
}

output "sg_db_id" {
  value = aws_security_group.rds_sg.id
}