# Named after the service so Xora finds it: for an alert with service=<name>, Xora queries the log group <name>.
resource "aws_cloudwatch_log_group" "app" {
  name              = var.service_name
  retention_in_days = 3
}

resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "${var.name_prefix}-app-errors"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "ERROR"

  metric_transformation {
    name          = "AppErrorCount"
    namespace     = "XoraTest"
    value         = "1"
    default_value = "0"
  }
}
