output "api_gateway_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.gw.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
}
