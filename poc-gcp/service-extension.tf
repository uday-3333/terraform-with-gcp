locals {
  # Sites with enable_extension = true get the full Option B leg
  extension_sites = { for k, s in local.sites : k => s if s.enable_extension }
}

# Serverless NEG for the decision Cloud Run service (one per extension-enabled site)
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

# Backend service for the decision Cloud Run service (one per extension-enabled site)
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

# LB Traffic Extension — intercepts every request and calls the decision service
# The decision service adds x-maintenance-bypass header; LB routes based on it
resource "google_network_services_lb_traffic_extension" "maintenance" {
  for_each              = local.extension_sites
  name                  = substr("${local.https_lb_name_prefix}-${each.key}-ext-maintenance", 0, 63)
  project               = local.project_id
  location              = "global"
  description           = "Option D+ dynamic exception evaluation for ${each.key}"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  forwarding_rules = [module.cloud_https_lbs["${each.key}-lb"].https_forwarding_rule_id]

  extension_chains {
    name = "${each.key}-maintenance-chain"

    match_condition {
      cel_expression = "true"
    }

    extensions {
      name             = "${each.key}-decision"
      authority        = "maintenance-decision.internal"
      service          = google_compute_backend_service.decision[each.key].self_link
      timeout          = "5s"
      fail_open        = true
      supported_events = ["REQUEST_HEADERS"]
    }
  }
}
