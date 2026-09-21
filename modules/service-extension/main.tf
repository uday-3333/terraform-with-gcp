# ============================================================================
# Service Extension — LB Traffic Extension (Callout)
# ============================================================================
# Attaches a Service Extensions callout chain to a global forwarding rule.
# Every matched request is forwarded via gRPC to the decision backend service
# (Cloud Run) before reaching the origin backend.
#
# fail_open = true  → origin receives the request if the callout times out/fails
# fail_open = false → 503 is returned to the client on callout failure

resource "google_network_services_lb_traffic_extension" "this" {
  name                  = var.name
  project               = var.project_id
  location              = "global"
  load_balancing_scheme = "EXTERNAL_MANAGED"

  forwarding_rules = [var.forwarding_rule_id]

  extension_chains {
    name = "${var.name}-chain"

    match_condition {
      cel_expression = var.cel_expression
    }

    extensions {
      name             = "${var.name}-callout"
      authority        = "maintenance-decision.internal"
      service          = var.backend_service_id
      timeout          = var.timeout
      fail_open        = var.fail_open
      supported_events = var.supported_events
    }
  }
}
