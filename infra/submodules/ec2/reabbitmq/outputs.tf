output "rabbit_instance_id"  {
  value = aws_instance.rabbit.id
}

output "rabbit_private_ip"   {
  value = aws_instance.rabbit.private_ip
}

output "rabbit_sg_id"        {
  value = aws_security_group.rabbit.id
}


