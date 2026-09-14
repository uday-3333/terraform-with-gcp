# ==========================================
# CLOUD RUN SERVICE MODULE (v2 / Admin API v2)
# ==========================================
# Deploys one or more Cloud Run services from a single module call using
# google_cloud_run_v2_service. Each entry in var.services is an independent
# service; its key is used as a stable identifier for state addressing.
resource "google_cloud_run_v2_service" "service" {
  for_each = var.services

  name     = substr(each.value.service_name, 0, 49)
  project  = var.project_id
  location = each.value.region

  ingress              = each.value.ingress_type
  deletion_protection  = each.value.deletion_protection
  default_uri_disabled = each.value.default_uri_disabled

  labels      = each.value.labels
  annotations = each.value.service_annotations

  template {
    service_account                  = each.value.service_account_email
    max_instance_request_concurrency = each.value.max_instance_request_concurrency
    timeout                          = "${each.value.timeout_seconds}s"
    execution_environment            = each.value.execution_environment
    session_affinity                 = each.value.session_affinity

    labels      = each.value.labels
    annotations = each.value.template_annotations

    scaling {
      min_instance_count = each.value.min_instances
      max_instance_count = each.value.max_instances
    }

    dynamic "vpc_access" {
      for_each = each.value.enable_vpc_egress && var.host_project_id != null && var.vpc_network != null && each.value.vpc_subnetwork != null ? [1] : []
      content {
        egress = each.value.vpc_egress_type

        network_interfaces {
          network    = "projects/${var.host_project_id}/global/networks/${var.vpc_network}"
          subnetwork = "projects/${var.host_project_id}/regions/${each.value.region}/subnetworks/${each.value.vpc_subnetwork}"
          tags       = length(each.value.tags) > 0 ? each.value.tags : null
        }
      }
    }

    containers {
      image = each.value.container_image

      resources {
        limits = {
          cpu    = each.value.cpu_limit
          memory = each.value.memory_limit
        }
        # v2 semantics: cpu_idle=true means CPU is throttled outside requests
        # (equivalent to v1 cpu-throttling=true). Keeping the caller-facing
        # cpu_throttling name for continuity.
        cpu_idle          = each.value.cpu_throttling
        startup_cpu_boost = each.value.startup_cpu_boost
      }

      ports {
        # "h2c" for gRPC/HTTP2 cleartext, "http1" otherwise.
        name           = each.value.grpc_enabled ? "h2c" : "http1"
        container_port = each.value.container_port
      }

      dynamic "startup_probe" {
        for_each = each.value.startup_probe_enabled ? [1] : []
        content {
          initial_delay_seconds = each.value.startup_probe_initial_delay
          timeout_seconds       = each.value.startup_probe_timeout
          period_seconds        = each.value.startup_probe_period
          failure_threshold     = each.value.startup_probe_failure_threshold
          http_get {
            path = each.value.startup_probe_path
            port = each.value.container_port
          }
        }
      }

      dynamic "liveness_probe" {
        for_each = each.value.liveness_probe_enabled ? [1] : []
        content {
          initial_delay_seconds = each.value.liveness_probe_initial_delay
          timeout_seconds       = each.value.liveness_probe_timeout
          period_seconds        = each.value.liveness_probe_period
          failure_threshold     = each.value.liveness_probe_failure_threshold
          http_get {
            path = each.value.liveness_probe_path
            port = each.value.container_port
          }
        }
      }

      dynamic "readiness_probe" {
        for_each = each.value.readiness_probe_enabled ? [1] : []
        content {
          timeout_seconds   = each.value.readiness_probe_timeout
          period_seconds    = each.value.readiness_probe_period
          failure_threshold = each.value.readiness_probe_failure_threshold
          http_get {
            path = each.value.readiness_probe_path
            port = each.value.container_port
          }
        }
      }

      dynamic "env" {
        for_each = each.value.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = each.value.environment_variables_secret
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret_name
              version = env.value.secret_key
            }
          }
        }
      }

      dynamic "volume_mounts" {
        for_each = each.value.volume_mounts
        content {
          name       = volume_mounts.value.name
          mount_path = volume_mounts.value.mount_path
        }
      }
    }

    dynamic "volumes" {
      for_each = each.value.volumes
      content {
        name = volumes.value.name
        secret {
          secret       = volumes.value.secret_name
          default_mode = 0644
          items {
            path    = volumes.value.path
            version = volumes.value.secret_key
          }
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].containers[0].image,
      template[0].containers[0].name,
      template[0].containers[0].env,
      template[0].scaling[0].max_instance_count,
      template[0].scaling[0].min_instance_count,
      # template[0].containers[0].resources,
      template[0].containers[0].startup_probe,
      # template[0].containers[0].liveness_probe,
      # template[0].vpc_access,
      template[0].volumes,
      template[0].containers[0].volume_mounts,
      template[0].revision, # Allow revision (tag) changes
      template[0].annotations,
    ]
  }
}

# Grants allUsers roles/run.invoker when allow_public_access = true.
# resource "google_cloud_run_v2_service_iam_member" "public_access" {
#   for_each = {
#     for k, s in var.services : k => s
#     if s.allow_public_access
#   }

#   project  = google_cloud_run_v2_service.service[each.key].project
#   location = google_cloud_run_v2_service.service[each.key].location
#   name     = google_cloud_run_v2_service.service[each.key].name
#   role     = "roles/run.invoker"
#   member   = "allUsers"
# }