variable "region" {
  description = "AWS region for the test lab."
  type        = string
  default     = "ap-southeast-1"
}

variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
  default     = "xora-test"
}

variable "xora_webhook_url" {
  description = "Xora Resolve HTTPS endpoint that receives SNS notifications (from the Xora CloudWatch connector settings)."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.xora_webhook_url == null ? true : startswith(var.xora_webhook_url, "https://")
    error_message = "xora_webhook_url must start with https://"
  }
}

variable "xora_gateway_principal_arn" {
  description = "Gateway principal ARN shown in the Xora connector 'Assume role' tab."
  type        = string
  default     = "arn:aws:iam::098640806013:role/techx-xora-dev-xora-gateway"
}

variable "xora_external_id" {
  description = "External ID shown in the Xora connector 'Assume role' tab."
  type        = string
  sensitive   = true
}

variable "xora_permissions_policy_json" {
  description = "Optional: the exact permissions policy JSON from the Xora UI. null = use the built-in read-only + SNS subscribe policy."
  type        = string
  default     = null
}

variable "xora_endpoint_auto_confirms" {
  description = "true if Xora Resolve confirms the SNS subscription automatically. Set false if you must confirm by hand with the SubscribeURL."
  type        = bool
  default     = true
}

variable "my_ip_cidr" {
  description = "Optional: your public IP (x.x.x.x/32), so you can open the demo app on :8080 in a browser. Leave null to keep it closed (SSM still works)."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 instance type (t3.micro is free-tier eligible in ap-southeast-1)."
  type        = string
  default     = "t3.micro"
}

variable "detailed_monitoring" {
  description = "Enable 1-minute EC2 metrics (~USD 2/month). false = free, CPU alarm uses 5-minute periods and fires more slowly."
  type        = bool
  default     = false
}

variable "service_name" {
  description = "Fixed service name used as the CloudWatch dimension of the demo alarm (app-down), so the service shown in Xora does not change when the EC2 instance is replaced."
  type        = string
  default     = "xora-test-app"
}
