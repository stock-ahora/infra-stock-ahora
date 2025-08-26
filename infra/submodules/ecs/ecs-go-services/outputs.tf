output "aws_lb_nlb_arn" {
  value = aws_lb.nlb.arn
}

output "api_ports" {
  value = local.api_ports
}

output "dns_name" {
  value = aws_lb.nlb.dns_name
}

