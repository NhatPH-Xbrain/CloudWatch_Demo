resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-xora-resolve-alerts"
}

# CloudWatch alarms -> SNS -> Xora Resolve webhook.
# Only created when xora_webhook_url is set; with the assume-role connector Xora can subscribe itself.
resource "aws_sns_topic_subscription" "xora" {
  count                  = var.xora_webhook_url == null ? 0 : 1
  topic_arn              = aws_sns_topic.alerts.arn
  protocol               = "https"
  endpoint               = var.xora_webhook_url
  endpoint_auto_confirms = var.xora_endpoint_auto_confirms
}
