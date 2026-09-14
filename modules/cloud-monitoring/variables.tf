variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "notification_channels" {
  description = "List of notification channel resource paths for alerts (e.g., projects/PROJECT/notificationChannels/1234567890)"
  type        = list(string)
  default     = []
}

variable "monitoring" {
  description = "Monitoring configuration for all components"
  type = object({
    enable_dashboard = optional(bool, true)
    enable_alerts    = optional(bool, true)
    cloud_run_alerts = optional(bool, true)
    cloud_sql_alerts = optional(bool, true)
    lb_alerts        = optional(bool, true)
    uptime_checks    = optional(list(string), [])
  })
  default = {}
}

variable "cloud_run" {
  description = "Cloud Run services to monitor. Key is stable identifier."
  type = map(object({
    service_name         = string
    service_url          = optional(string)
    error_rate_threshold = optional(number, 5)
    latency_threshold    = optional(number, 1000)
  }))
  default = {}
}

variable "cloud_sql" {
  description = "Cloud SQL instances to monitor. Key is stable identifier."
  type = map(object({
    instance_name        = string
    cpu_threshold        = optional(number, 80)
    memory_threshold     = optional(number, 85)
    connection_threshold = optional(number, 80)
  }))
  default = {}
}

variable "load_balancer" {
  description = "HTTPS Load Balancer resources to monitor. Key is stable identifier."
  type = map(object({
    resource_name        = string
    error_rate_threshold = optional(number, 5)
    latency_threshold    = optional(number, 1000)
  }))
  default = {}
}

variable "cloud_storage" {
  description = "Cloud Storage buckets to monitor. Key is stable identifier."
  type = map(object({
    bucket_name = string
  }))
  default = {}
}

variable "pubsub" {
  description = "Pub/Sub topics/subscriptions to monitor. Key is stable identifier."
  type = map(object({
    resource_name     = string
    backlog_threshold = optional(number, 100)
  }))
  default = {}
}
