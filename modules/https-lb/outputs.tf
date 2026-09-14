# ============================================================================
# Load Balancer Outputs
# ============================================================================

output "load_balancer_ip_address" {
  description = "External static IP address of the load balancer"
  value       = google_compute_global_address.static_ip.address
}

output "load_balancer_ip_address_name" {
  description = "Name of the static IP address resource"
  value       = google_compute_global_address.static_ip.name
}

# ============================================================================
# Forwarding Rule Outputs
# ============================================================================
output "https_forwarding_rule_name" {
  description = "Name of the HTTPS global forwarding rule"
  value       = google_compute_global_forwarding_rule.https.name
}

output "https_forwarding_rule_id" {
  description = "ID of the HTTPS global forwarding rule"
  value       = google_compute_global_forwarding_rule.https.id
}

output "http_forwarding_rule_name" {
  description = "Name of the HTTP global forwarding rule (redirects to HTTPS)"
  value       = google_compute_global_forwarding_rule.http.name
}

# ============================================================================
# SSL Certificate Outputs
# ============================================================================

output "managed_certificate_name" {
  description = "Name of the Certificate Manager certificate"
  value       = google_certificate_manager_certificate.https.name
}

output "managed_certificate_id" {
  description = "ID of the Certificate Manager certificate"
  value       = google_certificate_manager_certificate.https.id
}

output "managed_certificate_status" {
  description = "Status of the Certificate Manager certificate"
  value       = try(google_certificate_manager_certificate.https.managed[0].state, "PROVISIONING")
}

output "managed_certificate_domains" {
  description = "Domains covered by the Certificate Manager certificate"
  value       = var.domain_names
}

output "certificate_dns_authorization_records" {
  description = "DNS authorization CNAME records required for certificate validation (keyed by domain)"
  value = {
    for domain, auth in google_certificate_manager_dns_authorization.domain_auth :
    domain => {
      name = auth.dns_resource_record[0].name
      type = auth.dns_resource_record[0].type
      data = auth.dns_resource_record[0].data
    }
  }
}

output "ssl_policy_self_link" {
  description = "Effective SSL policy self_link attached to the HTTPS proxy"
  value       = google_compute_target_https_proxy.https.ssl_policy
}

output "module_managed_ssl_policy_name" {
  description = "Name of the module-managed SSL policy (null when external policy is provided)"
  value       = var.ssl_policy_self_link == null ? google_compute_ssl_policy.default_ssl_policy[0].name : null
}

# ============================================================================
# Multi-Service Backend Service Outputs
# ============================================================================

output "backend_services" {
  description = "Map of all backend services by service name"
  value = {
    for service_name, backend in google_compute_backend_service.cloud_run :
    service_name => {
      name      = backend.name
      id        = backend.id
      self_link = backend.self_link
    }
  }
}

output "backend_service_ids" {
  description = "List of all backend service IDs"
  value       = [for backend in google_compute_backend_service.cloud_run : backend.id]
}

# ============================================================================
# Multi-Service Serverless NEG Outputs
# ============================================================================

output "cloud_run_negs" {
  description = "Map of all Cloud Run serverless NEGs by service name"
  value = {
    for service_name, neg in google_compute_region_network_endpoint_group.cloud_run_neg :
    service_name => {
      name = neg.name
      id   = neg.id
    }
  }
}

output "cloud_run_neg_ids" {
  description = "List of all Cloud Run NEG IDs"
  value       = [for neg in google_compute_region_network_endpoint_group.cloud_run_neg : neg.id]
}

# ============================================================================
# URL Map Outputs
# ============================================================================

output "url_map_name" {
  description = "Name of the URL map"
  value       = google_compute_url_map.https.name
}

output "url_map_id" {
  description = "ID of the URL map"
  value       = google_compute_url_map.https.id
}

# ============================================================================
# HTTPS Proxy Outputs
# ============================================================================
output "https_proxy_name" {
  description = "Name of the target HTTPS proxy"
  value       = google_compute_target_https_proxy.https.name
}

output "https_proxy_id" {
  description = "ID of the target HTTPS proxy"
  value       = google_compute_target_https_proxy.https.id
}

# ============================================================================
# Cloud Armor Outputs
# ============================================================================

output "cloud_armor_policy_name" {
  description = "Per-service security policy assignment map (service name => policy identifier)"
  value = {
    for service in var.cloud_run_services :
    service.name => service.security_policy
  }
}

output "cloud_armor_policy_id" {
  description = "Per-service security policy assignment map (service name => policy identifier)"
  value = {
    for service in var.cloud_run_services :
    service.name => service.security_policy
  }
}

output "cloud_armor_enabled" {
  description = "Whether a security policy is assigned for all Cloud Run services"
  value = alltrue([
    for service in var.cloud_run_services : length(trimspace(service.security_policy)) > 0
  ])
}

# ============================================================================
# Logging Configuration Outputs
# ============================================================================

output "logging_enabled" {
  description = "Whether logging is enabled for backend services"
  value       = var.enable_logging
}

output "logging_sample_rate" {
  description = "Logging sample rate (0.0 to 1.0)"
  value       = var.logging_sample_rate
}

# ============================================================================
# CDN Configuration Outputs
# ============================================================================

output "cdn_enabled" {
  description = "Whether Cloud CDN is enabled"
  value       = var.enable_cdn
}

output "cdn_effective_cache_mode" {
  description = "Per-service effective Cloud CDN cache mode (service override or global default)"
  value = {
    for service in var.cloud_run_services :
    service.name => try(service.cdn_policy.cache_mode, var.global_default_cdn_policy.cache_mode)
  }
}

# ============================================================================
# DNS Configuration Instructions
# ============================================================================

output "dns_configuration_instructions" {
  description = "Instructions for configuring external DNS"
  value       = <<-EOT
    To complete the setup, configure DNS records in your external DNS provider:
    
    For each domain in ${join(", ", var.domain_names)}:
      Type: A Record
      Name: (subdomain or @ for root)
      Value: ${google_compute_global_address.static_ip.address}
      TTL: 300 (or your preferred TTL)

    For certificate validation, add these CNAME records:
${join("\n", [for domain, auth in google_certificate_manager_dns_authorization.domain_auth : "      - ${domain}: ${auth.dns_resource_record[0].name} ${auth.dns_resource_record[0].type} ${auth.dns_resource_record[0].data}"])}
    
    The Certificate Manager certificate requires DNS validation. After DNS records
    are created, the certificate will automatically transition to ACTIVE state.
    This typically takes 5-15 minutes but can take up to 24 hours.
    
    To check certificate status, run:
      gcloud certificate-manager certificates describe ${google_certificate_manager_certificate.https.name} --location=global --project=${var.project_id}
    EOT
}

# ============================================================================
# Debugging and Troubleshooting Outputs
# ============================================================================

output "project_id" {
  description = "GCP Project ID"
  value       = var.project_id
}

output "region" {
  description = "Default region used when a service omits cloud_run_service_region"
  value       = var.region
}

output "cloud_run_services_summary" {
  description = "Summary of configured Cloud Run services with routing details"
  value = [
    for service in var.cloud_run_services : {
      name            = service.name
      service_name    = service.cloud_run_service_name
      region          = service.cloud_run_service_region != null ? service.cloud_run_service_region : var.region
      backend_service = google_compute_backend_service.cloud_run[service.name].name
      neg             = google_compute_region_network_endpoint_group.cloud_run_neg[service.name].name
      path_rules      = [for rule in service.path_rules : rule.paths]
      host_rules      = [for rule in service.host_rules : rule.hosts]
    }
  ]
}

output "all_resource_labels" {
  description = "Labels applied to all resources"
  value       = var.labels
}

output "lb_name_prefix" {
  description = "Prefix used for all resource names"
  value       = var.lb_name_prefix
}

# ============================================================================
# Routing Configuration Summary
# ============================================================================

output "routing_configuration" {
  description = "Detailed routing configuration for all services"
  value = {
    default_service_name = var.cloud_run_services[0].name
    total_services       = length(var.cloud_run_services)
    services_with_host_rules = [
      for service in var.cloud_run_services :
      service.name
      if length(service.host_rules) > 0
    ]
    services_with_path_rules = [
      for service in var.cloud_run_services :
      service.name
      if length(service.path_rules) > 0
    ]
  }
}