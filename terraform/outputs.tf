output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_instance.app.public_ip
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "xora_role_arn" {
  description = "Paste into the Xora connector 'Role ARN' field."
  value       = aws_iam_role.xora.arn
}

output "xora_connector_settings" {
  value = {
    aws_region = var.region
    sns_topic  = aws_sns_topic.alerts.arn
    role_arn   = aws_iam_role.xora.arn
  }
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "ssm_session_command" {
  value = "aws ssm start-session --region ${var.region} --target ${aws_instance.app.id}"
}

output "service_name" {
  description = "Service value Xora shows for the demo alarm (xora-test-app-down). Use it in the Xora incident rule."
  value       = var.service_name
}
