output "vpc_id" { value = aws_vpc.this.id }

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_app_subnet_ids" {
  value = [for s in aws_subnet.private_app : s.id]
}

output "private_data_subnet_ids" {
  value = [for s in aws_subnet.private_data : s.id]
}

output "private_app_subnet_cidrs" {
  value = [for s in aws_subnet.private_app : s.cidr_block]
}

output "sg_alb_id"       {
  value = aws_security_group.alb.id
}
output "sg_app_id"       {
  value = aws_security_group.app.id
}
output "sg_db_id"        {
  value = aws_security_group.db.id
}
