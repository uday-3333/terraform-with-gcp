# ============================================================================
# Global Static IP Address for Load Balancer
# ============================================================================
# Reserve a global static IP address for the load balancer. This IP address
# is used for DNS configuration of custom domains and is shared by both
# HTTPS and HTTP forwarding rules. A global address is required because
# the load balancer distributes traffic globally.

resource "google_compute_global_address" "static_ip" {
  name         = substr("${var.lb_name_prefix}-ip", 0, 63)
  project      = var.project_id
  address_type = "EXTERNAL"
  ip_version   = "IPV4"

  labels = merge(
    local.sanitized_labels,
    {
      name = substr("${var.lb_name_prefix}-ip", 0, 63)
    }
  )
}

# ============================================================================
# Global Forwarding Rule (HTTPS - Port 443)
# ============================================================================
# The HTTPS forwarding rule uses the reserved static IP address and routes
# encrypted traffic (port 443) to the HTTPS target proxy for processing.

resource "google_compute_global_forwarding_rule" "https" {
  name                  = substr("${var.lb_name_prefix}-forwarding-rule", 0, 63)
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.https.id
  ip_address            = google_compute_global_address.static_ip.id

  labels = merge(
    local.sanitized_labels,
    {
      name = substr("${var.lb_name_prefix}-forwarding-rule", 0, 63)
    }
  )

  depends_on = [google_compute_target_https_proxy.https]
}

# ============================================================================
# Global Forwarding Rule (HTTP - Port 80)
# ============================================================================
# The HTTP forwarding rule uses the same reserved static IP address and routes
# unencrypted traffic (port 80) to the HTTP target proxy, which redirects to HTTPS.

resource "google_compute_global_forwarding_rule" "http" {
  name                  = substr("${var.lb_name_prefix}-http-forwarding-rule", 0, 63)
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_redirect.id
  ip_address            = google_compute_global_address.static_ip.id

  labels = merge(
    local.sanitized_labels,
    {
      name = substr("${var.lb_name_prefix}-http-forwarding-rule", 0, 63)
    }
  )

  depends_on = [google_compute_target_http_proxy.http_redirect]
}

# ============================================================================
# HTTPS Target Proxy
# ============================================================================
# The target proxy terminates HTTPS connections (using Certificate Manager)
# and forwards traffic to the HTTPS URL map for request routing logic.

resource "google_compute_ssl_policy" "default_ssl_policy" {
  count   = var.ssl_policy_self_link == null ? 1 : 0
  name    = substr("${var.lb_name_prefix}-ssl-policy", 0, 63)
  project = var.project_id

  min_tls_version = "TLS_1_2"
  profile         = "MODERN"
}


resource "google_compute_target_https_proxy" "https" {
  name            = substr("${var.lb_name_prefix}-https-proxy", 0, 63)
  project         = var.project_id
  url_map         = google_compute_url_map.https.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.https.id}"
  ssl_policy      = var.ssl_policy_self_link != null ? var.ssl_policy_self_link : google_compute_ssl_policy.default_ssl_policy[0].self_link

  depends_on = [
    google_certificate_manager_certificate_map_entry.domain_entries,
    google_compute_url_map.https
  ]
}

# ============================================================================
# HTTP Target Proxy
# ============================================================================
# The HTTP proxy handles incoming HTTP traffic on port 80 and forwards it
# to the HTTP URL map, which redirects to HTTPS.

resource "google_compute_target_http_proxy" "http_redirect" {
  name    = substr("${var.lb_name_prefix}-http-proxy", 0, 63)
  project = var.project_id
  url_map = google_compute_url_map.http_redirect.id
}

# ============================================================================
# Google-Managed SSL Certificate
# ============================================================================
# Certificate Manager DNS authorizations are created for each domain so DNS
# ownership can be proven with CNAME records in any external DNS provider.
resource "google_certificate_manager_dns_authorization" "domain_auth" {
  for_each = toset(var.domain_names)

  name    = substr("${var.lb_name_prefix}-dnsauth-${substr(md5(each.key), 0, 8)}", 0, 63)
  project = var.project_id
  domain  = each.key
  type    = "FIXED_RECORD"
}

# Certificate Manager certificate references all requested domains and the
# corresponding DNS authorizations.
resource "google_certificate_manager_certificate" "https" {
  name    = substr("${var.lb_name_prefix}-cm-cert", 0, 63)
  project = var.project_id

  managed {
    domains = var.domain_names
    dns_authorizations = [
      for domain in sort(keys(google_certificate_manager_dns_authorization.domain_auth)) :
      google_certificate_manager_dns_authorization.domain_auth[domain].id
    ]
  }
}

# A certificate map allows HTTPS proxy attachment for Certificate Manager certs.
resource "google_certificate_manager_certificate_map" "https" {
  name    = substr("${var.lb_name_prefix}-cert-map", 0, 63)
  project = var.project_id
}

resource "google_certificate_manager_certificate_map_entry" "domain_entries" {
  for_each = toset(var.domain_names)

  name         = substr("${var.lb_name_prefix}-cert-entry-${substr(md5(each.key), 0, 8)}", 0, 63)
  project      = var.project_id
  map          = google_certificate_manager_certificate_map.https.name
  hostname     = each.key
  certificates = [google_certificate_manager_certificate.https.id]
}

# ============================================================================
# HTTPS URL Map Configuration (Multi-Service Routing)
# ============================================================================
# The URL map defines request routing rules for HTTPS traffic. Routes are
# dynamically built from cloud_run_services configuration:
#
# ROUTING LOGIC:
# - Host rules: Match requests by hostname (e.g., api.example.com)
#   Routes to a path_matcher for that service
# - Path matchers: Match requests within a host rule by URL path
#   Each service gets its own path_matcher with its path_rules
# - Default service: First service in cloud_run_services list
#   Receives traffic matching no other rules
#
# TRAFFIC FLOW:
# 1. Request arrives with Host header (e.g., "api.example.com")
# 2. Check host_rules: if match found, use that service's path_matcher
# 3. Check path_rules within path_matcher: route to matching service
# 4. If no match, send to default_service (first service)
#
# IMPORTANT: At least one service should have path_rules covering "/" or "/*"
# to catch unmatched traffic. Otherwise, traffic may fail with 404.

locals {
  sanitized_labels = {
    for k, v in var.labels :
    k => substr(tostring(v), 0, 63)
  }

  # Sample structure:
  # {
  #   app1 = { name = "app1", host_rules = [{ hosts = ["app1.example.com"] }], path_rules = [...] }
  #   app2 = { name = "app2", host_rules = [], path_rules = [...] }
  # }
  services_by_name = { for service in var.cloud_run_services : service.name => service }

  # Sample structure (only services that define host_rules):
  # {
  #   app1 = { name = "app1", host_rules = [{ hosts = ["app1.example.com"] }], ... }
  # }
  services_with_host_rules = {
    for name, service in local.services_by_name :
    name => service
    if length(service.host_rules) > 0
  }

  # Sample structure (only services that do not define host_rules):
  # {
  #   app2 = { name = "app2", host_rules = [], path_rules = [{ paths = ["/app2/*"] }], ... }
  # }
  services_without_host_rules = {
    for name, service in local.services_by_name :
    name => service
    if length(service.host_rules) == 0
  }

  # Sample structure:
  # [
  #   { service_name = "app2", paths = ["/app2/*"] },
  #   { service_name = "app3", paths = ["/shared/*", "/public/*"] }
  # ]
  flattened_path_rules = flatten([
    for service in values(local.services_without_host_rules) : [
      for rule in service.path_rules : {
        service_name = service.name
        paths        = rule.paths
      }
    ]
  ])

}

resource "google_compute_url_map" "https" {
  name            = substr("${var.lb_name_prefix}-url-map", 0, 63)
  default_service = google_compute_backend_service.cloud_run[var.cloud_run_services[0].name].id
  project         = var.project_id
  description     = "URL map for external HTTPS load balancer routing to multiple Cloud Run services"

  # Build host rules from services with host_rules
  dynamic "host_rule" {
    for_each = local.services_with_host_rules
    content {
      hosts        = flatten(host_rule.value.host_rules[*].hosts)
      path_matcher = "path-matcher-${host_rule.value.name}"
    }
  }

  # Add a wildcard host rule when path-only services are present.
  # This ensures path-only service definitions are always reachable.
  dynamic "host_rule" {
    for_each = length(local.flattened_path_rules) > 0 ? [1] : []
    content {
      hosts        = ["*"]
      path_matcher = "path-matcher-global"
    }
  }

  # Build path matchers from services
  dynamic "path_matcher" {
    for_each = local.services_by_name
    content {
      name            = "path-matcher-${path_matcher.value.name}"
      default_service = google_compute_backend_service.cloud_run[path_matcher.value.name].id

      # Add path rules for this service if configured
      dynamic "path_rule" {
        for_each = path_matcher.value.path_rules[*].paths
        content {
          paths   = path_rule.value
          service = google_compute_backend_service.cloud_run[path_matcher.value.name].id
        }
      }
    }
  }

  # Global path matcher used by wildcard host rule for cross-service path routing.
  dynamic "path_matcher" {
    for_each = length(local.flattened_path_rules) > 0 ? [1] : []
    content {
      name            = "path-matcher-global"
      default_service = google_compute_backend_service.cloud_run[var.cloud_run_services[0].name].id

      dynamic "path_rule" {
        for_each = local.flattened_path_rules
        content {
          paths   = path_rule.value.paths
          service = google_compute_backend_service.cloud_run[path_rule.value.service_name].id
        }
      }
    }
  }

  depends_on = [google_compute_backend_service.cloud_run]
}

# ============================================================================
# HTTP to HTTPS Redirect URL Map
# ============================================================================
# URL map for the HTTP forwarding rule that redirects all traffic to HTTPS.
# This ensures all traffic is encrypted and complies with security best practices.

resource "google_compute_url_map" "http_redirect" {
  name    = substr("${var.lb_name_prefix}-http-redirect", 0, 63)
  project = var.project_id

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# ============================================================================
# Dynamic Backend Services (One per Cloud Run Service)
# ============================================================================
# Each backend service connects to its corresponding serverless NEG and configures
# CDN, connection draining, security policies, and logging.
# Logging is now mandatory for all backend services.

resource "google_compute_backend_service" "cloud_run" {
  for_each = { for service in var.cloud_run_services : service.name => service }

  name                            = substr("${var.lb_name_prefix}-bsvc-${each.value.name}", 0, 63)
  protocol                        = "HTTP2"
  port_name                       = "http"
  project                         = var.project_id
  load_balancing_scheme           = "EXTERNAL_MANAGED"
  enable_cdn                      = var.enable_cdn
  session_affinity                = var.session_affinity
  connection_draining_timeout_sec = var.connection_draining_timeout_seconds
  timeout_sec                     = var.request_timeout_seconds
  security_policy                 = each.value.security_policy

  backend {
    group = google_compute_region_network_endpoint_group.cloud_run_neg[each.value.name].id
  }

  # Cloud CDN configuration
  dynamic "cdn_policy" {
    for_each = var.enable_cdn ? [1] : []
    content {
      cache_mode       = try(each.value.cdn_policy.cache_mode, var.global_default_cdn_policy.cache_mode)
      default_ttl      = try(each.value.cdn_policy.default_ttl_seconds, var.global_default_cdn_policy.default_ttl_seconds)
      max_ttl          = try(each.value.cdn_policy.max_ttl_seconds, var.global_default_cdn_policy.max_ttl_seconds)
      client_ttl       = try(each.value.cdn_policy.client_ttl_seconds, var.global_default_cdn_policy.client_ttl_seconds)
      negative_caching = try(each.value.cdn_policy.negative_caching, var.global_default_cdn_policy.negative_caching)

      cache_key_policy {
        include_host         = true
        include_protocol     = true
        include_query_string = true
      }

      dynamic "negative_caching_policy" {
        for_each = try(each.value.cdn_policy.negative_caching, var.global_default_cdn_policy.negative_caching) ? {
          for policy in try(each.value.cdn_policy.negative_caching_policies, var.global_default_cdn_policy.negative_caching_policies) :
          format("%03d", policy.code) => policy
        } : {}
        content {
          code = negative_caching_policy.value.code
          ttl  = negative_caching_policy.value.ttl
        }
      }
    }
  }

  # Logging configuration (mandatory)
  log_config {
    enable      = var.enable_logging
    sample_rate = var.logging_sample_rate
  }
}


# ============================================================================
# Dynamic Serverless Network Endpoint Groups (One per Cloud Run Service)
# ============================================================================
# Serverless NEGs represent each Cloud Run service and allow direct traffic
# routing from the load balancer to Cloud Run without requiring custom VPCs
# or network configuration. The target Cloud Run service is bound explicitly
# via cloud_run.service and region in each NEG.

resource "google_compute_region_network_endpoint_group" "cloud_run_neg" {
  for_each = { for service in var.cloud_run_services : service.name => service }

  name                  = substr("${var.lb_name_prefix}-neg-${each.value.name}", 0, 63)
  network_endpoint_type = "SERVERLESS"
  project               = var.project_id
  region                = each.value.cloud_run_service_region != null ? each.value.cloud_run_service_region : var.region

  cloud_run {
    service = each.value.cloud_run_service_name
  }
}