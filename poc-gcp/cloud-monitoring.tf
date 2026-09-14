# ==========================================
# CLOUD MONITORING MODULE
# ==========================================
# Creates monitoring dashboards, alert policies, and uptime checks
# for Cloud Run, Load Balancer, and other GCP infrastructure

module "cloud_monitoring" {
  source = "../modules/cloud-monitoring"

  project_id = local.project_id
  environment = local.environment

  # Notification channels for alerts
  notification_channels = local.notification_channels

  # Monitoring configuration
  monitoring = {
    enable_dashboard = true
    enable_alerts    = true
    cloud_run_alerts = true
    cloud_sql_alerts = false
    lb_alerts        = true  # Enable LB error rate (latency may need 10-15 min)
    uptime_checks    = ["https://opsnexus.blog"]
  }

  # Cloud Run services configuration
  cloud_run = {
    "gcp-poc-app" = {
      service_name         = module.cloud_run.service_names["gcp-poc-app"]
      error_rate_threshold = 5
      latency_threshold    = 1000
    }
  }

  # Cloud SQL configuration (empty for POC)
  cloud_sql = {}

  # Load Balancer configuration
  load_balancer = {
    "gcp-poc-lb" = {
      resource_name        = "elb-${local.common_name_prefix}-https-fr"
      error_rate_threshold = 5
      latency_threshold    = 1000
    }
  }

  # Cloud Storage configuration (optional)
  cloud_storage = {}

  # Pub/Sub configuration (optional)
  pubsub = {}

  depends_on = [
    module.cloud_run
  ]
}