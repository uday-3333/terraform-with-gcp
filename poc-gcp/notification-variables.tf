# ==========================================
# NOTIFICATION CHANNEL VARIABLES
# ==========================================

variable "enable_email_notifications" {
  description = "Enable email notifications for alerts"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address to send alert notifications"
  type        = string
  default     = "alerts@example.com"
  # Change to your actual email: "your-email@company.com"
}

variable "enable_slack_notifications" {
  description = "Enable Slack notifications for alerts"
  type        = bool
  default     = false
}

variable "slack_channel_name" {
  description = "Slack channel name for notifications (e.g., #alerts)"
  type        = string
  default     = "alerts"
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL"
  type        = string
  default     = ""
  sensitive   = true
  # Get this from: https://api.slack.com/apps > Your App > Incoming Webhooks
}

variable "enable_pagerduty_notifications" {
  description = "Enable PagerDuty notifications for alerts"
  type        = bool
  default     = false
}

variable "pagerduty_integration_key" {
  description = "PagerDuty integration key"
  type        = string
  default     = ""
  sensitive   = true
  # Get this from PagerDuty service integration settings
}

variable "additional_notification_channels" {
  description = "Additional notification channel resource IDs to attach to alerts"
  type        = list(string)
  default     = []
}
