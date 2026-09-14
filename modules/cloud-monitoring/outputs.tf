output "dashboard_id" {
  description = "Environment monitoring dashboard ID"
  value       = try(google_monitoring_dashboard.environment[0].id, null)
}

output "cloud_run_alerts" {
  description = "Cloud Run alert policy IDs"
  value = {
    error_rate = { for k, a in google_monitoring_alert_policy.cloud_run_error_rate : k => a.id }
    latency    = { for k, a in google_monitoring_alert_policy.cloud_run_latency : k => a.id }
  }
}

output "cloud_sql_alerts" {
  description = "Cloud SQL alert policy IDs"
  value = {
    cpu         = { for k, a in google_monitoring_alert_policy.cloud_sql_cpu : k => a.id }
    memory      = { for k, a in google_monitoring_alert_policy.cloud_sql_memory : k => a.id }
    connections = { for k, a in google_monitoring_alert_policy.cloud_sql_connections : k => a.id }
  }
}

output "lb_alerts" {
  description = "Load Balancer alert policy IDs"
  value = {
    error_rate = { for k, a in google_monitoring_alert_policy.lb_error_rate : k => a.id }
    latency    = { for k, a in google_monitoring_alert_policy.lb_latency : k => a.id }
  }
}

output "uptime_check_ids" {
  description = "Uptime check resource IDs"
  value       = { for k, u in google_monitoring_uptime_check_config.service : k => u.id }
}
