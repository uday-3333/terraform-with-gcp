locals {
  # Sites with enable_extension = true get the Service Extension callout leg
  extension_sites = { for k, s in local.sites : k => s if s.enable_extension }
}

# ============================================================================
# Serverless NEG — decision Cloud Run service (one per extension-enabled site)
# ============================================================================
resource "google_compute_region_network_endpoint_group" "decision_neg" {
  for_each              = local.extension_sites
  name                  = substr("${local.https_lb_name_prefix}-${each.key}-neg-decision", 0, 63)
  network_endpoint_type = "SERVERLESS"
  project               = local.project_id
  region                = local.region

  cloud_run {
    service = module.cloud_run.service_names["${each.key}-decision"]
  }
}

# ============================================================================
# Backend Service — decision Cloud Run NEG (one per extension-enabled site)
# ============================================================================
resource "google_compute_backend_service" "decision" {
  for_each              = local.extension_sites
  name                  = substr("${local.https_lb_name_prefix}-${each.key}-bsvc-decision", 0, 63)
  project               = local.project_id
  protocol              = "HTTP2"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.decision_neg[each.key].id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# ============================================================================
# Service Extension — reusable module (one per extension-enabled site)
# Intercepts every request and calls the decision Cloud Run service via gRPC.
# The decision service reads maintenance/redirects/vanities config from GCS
# and returns the appropriate action header back to the LB.
# fail_open = true ensures the site stays up if the callout service is down.
# ============================================================================
module "service_extension" {
  source   = "../modules/service-extension"
  for_each = local.extension_sites

  name               = substr("${local.https_lb_name_prefix}-${each.key}-ext-maintenance", 0, 63)
  project_id         = local.project_id
  forwarding_rule_id = module.cloud_https_lbs["${each.value.lb_key}"].https_forwarding_rule_id
  backend_service_id = google_compute_backend_service.decision[each.key].self_link
  timeout            = "5s"
  fail_open          = true
  cel_expression     = "true"
  supported_events   = ["REQUEST_HEADERS"]

  depends_on = [
    google_compute_backend_service.decision,
    module.cloud_https_lbs,
  ]
}
