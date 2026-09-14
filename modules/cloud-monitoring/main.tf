# ==========================================
# CLOUD MONITORING MODULE
# ==========================================
# Creates monitoring dashboards, alert policies, and uptime checks
# for GCP infrastructure: Cloud Run, Cloud SQL, HTTPS LB, Storage, Pub/Sub

locals {
  enabled_alerts    = var.monitoring.enable_alerts
  enabled_dashboard = var.monitoring.enable_dashboard

  # Cloud Run filters
  cr_filters = {
    for k, s in var.cloud_run : k => {
      request_count  = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${s.service_name}\" AND metric.type = \"run.googleapis.com/request_count\""
      error_rate     = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${s.service_name}\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class != \"2xx\""
      latency        = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${s.service_name}\" AND metric.type = \"run.googleapis.com/request_latencies\""
      instance_count = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${s.service_name}\" AND metric.type = \"run.googleapis.com/container/instance_count\""
    }
  }

  # Cloud SQL filters
  sql_filters = {
    for k, i in var.cloud_sql : k => {
      cpu         = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${i.instance_name}\" AND metric.type = \"cloudsql.googleapis.com/database/cpu/utilization\""
      memory      = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${i.instance_name}\" AND metric.type = \"cloudsql.googleapis.com/database/memory/utilization\""
      connections = "resource.type = \"cloudsql_database\" AND resource.labels.database_id = \"${i.instance_name}\" AND metric.type = \"cloudsql.googleapis.com/database/network/connections\""
    }
  }

  # HTTPS LB filters
  lb_filters = {
    for k, l in var.load_balancer : k => {
      request_count = "resource.type = \"https_lb_rule\" AND resource.labels.forwarding_rule_name = \"${l.resource_name}\" AND metric.type = \"loadbalancing.googleapis.com/https/request_count\""
      error_rate    = "resource.type = \"https_lb_rule\" AND resource.labels.forwarding_rule_name = \"${l.resource_name}\" AND metric.type = \"loadbalancing.googleapis.com/https/request_count\" AND metric.labels.response_code_class > 3"
      latency       = "resource.type = \"https_lb_rule\" AND resource.labels.forwarding_rule_name = \"${l.resource_name}\" AND metric.type = \"loadbalancing.googleapis.com/https/request_latencies\""
    }
  }

  # Cloud Storage filters
  cs_filters = {
    for k, b in var.cloud_storage : k => {
      errors     = "resource.type = \"gcs_bucket\" AND resource.labels.bucket_name = \"${b.bucket_name}\" AND metric.type = \"storage.googleapis.com/storage/total_bytes\""
      access_log = "resource.type = \"gcs_bucket\" AND resource.labels.bucket_name = \"${b.bucket_name}\" AND metric.type = \"storage.googleapis.com/storage/object_count\""
    }
  }

  # Pub/Sub filters
  ps_filters = {
    for k, p in var.pubsub : k => {
      backlog_bytes = "resource.type = \"pubsub_subscription\" AND resource.labels.subscription_id = \"${p.resource_name}\" AND metric.type = \"pubsub.googleapis.com/subscription/num_undelivered_messages\""
      latency       = "resource.type = \"pubsub_subscription\" AND resource.labels.subscription_id = \"${p.resource_name}\" AND metric.type = \"pubsub.googleapis.com/subscription/oldest_unacked_message_age\""
    }
  }
}

# ==========================================
# CLOUD RUN ALERTS
# ==========================================

resource "google_monitoring_alert_policy" "cloud_run_error_rate" {
  for_each = var.monitoring.cloud_run_alerts && local.enabled_alerts ? var.cloud_run : {}

  display_name = "cloud-run-${each.key}-high-error-rate"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Error rate > ${each.value.error_rate_threshold} req/s"

    condition_threshold {
      filter          = local.cr_filters[each.key].error_rate
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.error_rate_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.notification_channels

  documentation {
    content   = "Cloud Run ${each.value.service_name} error rate exceeded ${each.value.error_rate_threshold} req/s"
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "86400s"
  }
}

resource "google_monitoring_alert_policy" "cloud_run_latency" {
  for_each = var.monitoring.cloud_run_alerts && local.enabled_alerts ? var.cloud_run : {}

  display_name = "cloud-run-${each.key}-high-latency"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Latency (p95) > ${each.value.latency_threshold}ms"

    condition_threshold {
      filter          = local.cr_filters[each.key].latency
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.latency_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_95"
      }
    }
  }

  notification_channels = var.notification_channels

  documentation {
    content   = "Cloud Run ${each.value.service_name} latency (p95) exceeded ${each.value.latency_threshold}ms"
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "86400s"
  }
}

# ==========================================
# CLOUD SQL ALERTS
# ==========================================

resource "google_monitoring_alert_policy" "cloud_sql_cpu" {
  for_each = var.monitoring.cloud_sql_alerts && local.enabled_alerts ? var.cloud_sql : {}

  display_name = "cloud-sql-${each.key}-high-cpu"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "CPU > ${each.value.cpu_threshold}%"

    condition_threshold {
      filter          = local.sql_filters[each.key].cpu
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.cpu_threshold / 100

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels

  documentation {
    content   = "Cloud SQL ${each.value.instance_name} CPU exceeded ${each.value.cpu_threshold}%"
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "86400s"
  }
}

resource "google_monitoring_alert_policy" "cloud_sql_memory" {
  for_each = var.monitoring.cloud_sql_alerts && local.enabled_alerts ? var.cloud_sql : {}

  display_name = "cloud-sql-${each.key}-high-memory"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Memory > ${each.value.memory_threshold}%"

    condition_threshold {
      filter          = local.sql_filters[each.key].memory
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.memory_threshold / 100

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels

  documentation {
    content   = "Cloud SQL ${each.value.instance_name} Memory exceeded ${each.value.memory_threshold}%"
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "86400s"
  }
}

resource "google_monitoring_alert_policy" "cloud_sql_connections" {
  for_each = var.monitoring.cloud_sql_alerts && local.enabled_alerts ? var.cloud_sql : {}

  display_name = "cloud-sql-${each.key}-high-connections"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Connections > ${each.value.connection_threshold}%"

    condition_threshold {
      filter          = local.sql_filters[each.key].connections
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.connection_threshold / 100

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels

  documentation {
    content   = "Cloud SQL ${each.value.instance_name} connections exceeded ${each.value.connection_threshold}%"
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "86400s"
  }
}

# ==========================================
# HTTPS LOAD BALANCER ALERTS
# ==========================================

resource "google_monitoring_alert_policy" "lb_error_rate" {
  for_each = var.monitoring.lb_alerts && local.enabled_alerts ? var.load_balancer : {}

  display_name = "lb-${each.key}-high-error-rate"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Error rate > ${each.value.error_rate_threshold} req/s"

    condition_threshold {
      filter          = local.lb_filters[each.key].error_rate
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.error_rate_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.notification_channels

  documentation {
    content   = "Load Balancer ${each.value.resource_name} error rate exceeded ${each.value.error_rate_threshold} req/s"
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "86400s"
  }
}

resource "google_monitoring_alert_policy" "lb_latency" {
  for_each = false ? {} : {}  # Disabled: metric takes 15+ min to propagate. Enable manually after metric becomes available.

  display_name = "lb-${each.key}-high-latency"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Latency (p95) > ${each.value.latency_threshold}ms"

    condition_threshold {
      filter          = "resource.type = \"https_lb_rule\" AND resource.labels.forwarding_rule_name = \"${each.value.resource_name}\" AND metric.type = \"loadbalancing.googleapis.com/https/request_latencies\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.latency_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_95"
      }
    }
  }

  notification_channels = var.notification_channels

  documentation {
    content   = "Load Balancer ${each.value.resource_name} latency (p95) exceeded ${each.value.latency_threshold}ms"
    mime_type = "text/markdown"
  }

  alert_strategy {
    auto_close = "86400s"
  }
}

# ==========================================
# UPTIME CHECKS
# ==========================================

resource "google_monitoring_uptime_check_config" "service" {
  for_each = toset(var.monitoring.uptime_checks)

  display_name = "uptime-check-${each.value}"
  project      = var.project_id
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = regex("^[^/?:#]+", replace(replace(each.value, "https://", ""), "http://", ""))
    }
  }
}

# ==========================================
# DASHBOARDS
# ==========================================

resource "google_monitoring_dashboard" "environment" {
  count   = var.monitoring.enable_dashboard ? 1 : 0
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "${var.environment} - Environment Monitoring"
    mosaicLayout = {
      columns = 12
      tiles = concat(
        # Cloud Run tiles
        [
          for k, s in var.cloud_run : {
            xPos   = (index(keys(var.cloud_run), k) % 2) * 6
            yPos   = (index(keys(var.cloud_run), k) / 2) * 4
            width  = 6
            height = 4
            widget = {
              title = "Cloud Run: ${s.service_name}"
              xyChart = {
                dataSets = [{
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = local.cr_filters[k].request_count
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }]
                yAxis = {
                  label = "Requests/sec"
                  scale = "LINEAR"
                }
              }
            }
          }
        ],
        # Cloud SQL tiles
        [
          for k, i in var.cloud_sql : {
            xPos   = (index(keys(var.cloud_sql), k) % 2) * 6
            yPos   = 8 + ((index(keys(var.cloud_sql), k) / 2) * 4)
            width  = 6
            height = 4
            widget = {
              title = "Cloud SQL: ${i.instance_name} (CPU)"
              xyChart = {
                dataSets = [{
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = local.sql_filters[k].cpu
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }]
                yAxis = {
                  label = "CPU %"
                  scale = "LINEAR"
                }
              }
            }
          }
        ],
        # Load Balancer tiles
        [
          for k, l in var.load_balancer : {
            xPos   = (index(keys(var.load_balancer), k) % 2) * 6
            yPos   = 16 + ((index(keys(var.load_balancer), k) / 2) * 4)
            width  = 6
            height = 4
            widget = {
              title = "LB: ${l.resource_name}"
              xyChart = {
                dataSets = [{
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = local.lb_filters[k].request_count
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }]
                yAxis = {
                  label = "Requests/sec"
                  scale = "LINEAR"
                }
              }
            }
          }
        ]
      )
    }
  })
}
