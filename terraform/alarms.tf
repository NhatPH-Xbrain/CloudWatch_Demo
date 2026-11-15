locals {
  instance_id = aws_instance.app.id
  ec2_period  = var.detailed_monitoring ? 60 : 300
  actions     = [aws_sns_topic.alerts.arn]
}

# A1 - CPU spike (UC1, UC6, UC8)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-cpu-high"
  alarm_description   = "CPU on ${var.name_prefix}-app (${local.instance_id}) above 80%. Check top processes on the instance."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = local.instance_id }
  statistic           = "Average"
  period              = local.ec2_period
  evaluation_periods  = var.detailed_monitoring ? 2 : 1
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# A2 - application error burst from logs (UC2, UC6)
resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name          = "${var.name_prefix}-app-errors"
  alarm_description   = "demo-app logged 5+ ERROR lines per minute in log group ${aws_cloudwatch_log_group.app.name}."
  namespace           = "XoraTest"
  metric_name         = "AppErrorCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions

  depends_on = [aws_cloudwatch_log_metric_filter.app_errors]
}

# A3 - root disk filling up (UC3)
resource "aws_cloudwatch_metric_alarm" "disk_high" {
  alarm_name          = "${var.name_prefix}-disk-high"
  alarm_description   = "Root volume (/) on ${local.instance_id} above 85% used."
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = local.instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# A4 - memory pressure (UC4)
resource "aws_cloudwatch_metric_alarm" "mem_high" {
  alarm_name          = "${var.name_prefix}-mem-high"
  alarm_description   = "Memory on ${local.instance_id} above 80% used."
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { InstanceId = local.instance_id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# A5 - demo-app service down (UC5). Missing data is notBreaching so the alarm does not fire
# while the instance is still booting; a dead instance is covered by A6.
resource "aws_cloudwatch_metric_alarm" "app_down" {
  alarm_name          = "${var.name_prefix}-app-down"
  alarm_description   = "demo-app /health check failing on ${local.instance_id} (XoraTest/AppHealthy < 1)."
  namespace           = "XoraTest"
  metric_name         = "AppHealthy"
  dimensions          = { InstanceId = local.instance_id }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}

# A6 - EC2 instance status check (passive: fires on real host or OS problems)
resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${var.name_prefix}-status-check"
  alarm_description   = "EC2 instance status check failing on ${local.instance_id}."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  dimensions          = { InstanceId = local.instance_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
  ok_actions          = local.actions
}
