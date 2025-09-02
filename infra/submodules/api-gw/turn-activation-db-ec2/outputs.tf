output "invoke_urls" {
  value = {
    on  = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/on"
    off = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/off"
  }
}

output "api_key_value" {
  value     = random_password.api_key_value.result
  sensitive = true
}
