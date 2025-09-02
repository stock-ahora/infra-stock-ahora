output "lambda_invoke_arn" {
  description = "API Gateway invoke ARN"
  value = aws_lambda_function.switcher.invoke_arn
}

output "lambda_name" {
    description = "Lambda function name"
    value = aws_lambda_function.switcher.function_name
}


