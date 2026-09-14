# ==========================================
# NOTIFICATION CHANNELS
# ==========================================
# Configure notification channels for alerts (email, Slack, PagerDuty, etc.)
# Uncomment and customize based on your preferred notification method

# ==========================================
# EMAIL NOTIFICATION CHANNEL
# ==========================================
resource "google_monitoring_notification_channel" "email" {
  count           = var.enable_email_notifications ? 1 : 0
  display_name    = "Email - ${var.notification_email}"
  type            = "email"
  project         = local.project_id
  enabled         = true
  labels = {
    email_address = var.notification_email
  }
}

# ==========================================
# SLACK NOTIFICATION CHANNEL (Optional)
# ==========================================
# To use Slack:
# 1. Create a Slack App: https://api.slack.com/apps
# 2. Enable Incoming Webhooks
# 3. Create a webhook URL for your channel
# 4. Set the variable: var.slack_webhook_url

resource "google_monitoring_notification_channel" "slack" {
  count        = var.enable_slack_notifications ? 1 : 0
  display_name = "Slack - ${var.slack_channel_name}"
  type         = "slack"
  project      = local.project_id
  enabled      = true
  labels = {
    channel_name = var.slack_channel_name
  }
  sensitive_labels {
    auth_token = var.slack_webhook_url
  }
}

# ==========================================
# PAGERDUTY NOTIFICATION CHANNEL (Optional)
# ==========================================
# To use PagerDuty:
# 1. Create a service in PagerDuty
# 2. Get the integration key
# 3. Set the variable: var.pagerduty_integration_key

resource "google_monitoring_notification_channel" "pagerduty" {
  count        = var.enable_pagerduty_notifications ? 1 : 0
  display_name = "PagerDuty"
  type         = "pagerduty"
  project      = local.project_id
  enabled      = true
  sensitive_labels {
    service_key = var.pagerduty_integration_key
  }
}

# ==========================================
# COLLECT NOTIFICATION CHANNEL IDs
# ==========================================
# This list is used by monitoring module for alerts

locals {
  notification_channels = concat(
    var.enable_email_notifications ? [google_monitoring_notification_channel.email[0].id] : [],
    var.enable_slack_notifications ? [google_monitoring_notification_channel.slack[0].id] : [],
    var.enable_pagerduty_notifications ? [google_monitoring_notification_channel.pagerduty[0].id] : [],
    var.additional_notification_channels
  )
}

# ==========================================
# OUTPUT NOTIFICATION CHANNELS
# ==========================================

output "notification_channels" {
  description = "Created notification channel resource IDs"
  value = {
    email      = var.enable_email_notifications ? google_monitoring_notification_channel.email[0].id : null
    slack      = var.enable_slack_notifications ? google_monitoring_notification_channel.slack[0].id : null
    pagerduty  = var.enable_pagerduty_notifications ? google_monitoring_notification_channel.pagerduty[0].id : null
  }
}
