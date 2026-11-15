# IAM role that Xora Resolve assumes (connector "Assume role" tab).
# Trust and permissions policies match what the Xora connector UI provides.

data "aws_iam_policy_document" "xora_trust" {
  statement {
    sid     = "XoraGatewayAssumeRole"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [var.xora_gateway_principal_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.xora_external_id]
    }
  }

  statement {
    sid     = "XoraGatewayTagSession"
    actions = ["sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [var.xora_gateway_principal_arn]
    }
  }
}

resource "aws_iam_role" "xora" {
  name                 = "${var.name_prefix}-xora-resolve-connector"
  description          = "Assumed by Xora Resolve to read CloudWatch alarms/metrics/logs and subscribe to SNS."
  assume_role_policy   = data.aws_iam_policy_document.xora_trust.json
  max_session_duration = 3600
}

# Permissions policy from the Xora connector UI.
data "aws_iam_policy_document" "xora_default" {
  statement {
    actions = [
      "cloudwatch:DescribeAlarms",
      "cloudwatch:GetMetricData",
      "logs:StartQuery",
      "logs:GetQueryResults",
      "logs:StopQuery",
      "sns:ListTopics",
      "sns:Subscribe",
      "sns:Unsubscribe",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "xora" {
  name   = "${var.name_prefix}-xora-resolve-permissions"
  role   = aws_iam_role.xora.id
  policy = coalesce(var.xora_permissions_policy_json, data.aws_iam_policy_document.xora_default.json)
}
