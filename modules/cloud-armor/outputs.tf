/**
 * Outputs for Cloud Armor Security Policy Module - Multiple Policies
 */

# ========================================
# All Policies Output
# ========================================

output "policies" {
  description = "Map of all created Cloud Armor policies with their details"
  value = {
    for k, policy in google_compute_security_policy.policies : k => {
      id          = policy.id
      name        = policy.name
      self_link   = policy.self_link
      fingerprint = policy.fingerprint
      description = policy.description
    }
  }
}

# ========================================
# Individual Policy Attributes
# ========================================

output "policy_ids" {
  description = "Map of policy keys to policy IDs"
  value       = { for k, policy in google_compute_security_policy.policies : k => policy.id }
}

output "policy_names" {
  description = "Map of policy keys to policy names"
  value       = { for k, policy in google_compute_security_policy.policies : k => policy.name }
}

output "policy_self_links" {
  description = "Map of policy keys to policy self links (use these to attach to load balancers)"
  value       = { for k, policy in google_compute_security_policy.policies : k => policy.self_link }
}

output "policy_fingerprints" {
  description = "Map of policy keys to policy fingerprints (for change detection)"
  value       = { for k, policy in google_compute_security_policy.policies : k => policy.fingerprint }
}

# ========================================
# Policy Configuration Details
# ========================================

output "access_modes" {
  description = "Map of policy keys to their access modes (private or public)"
  value       = { for k, v in var.policies : k => v.access_mode }
}

output "default_rule_actions" {
  description = "Map of policy keys to their default rule actions"
  value       = { for k, config in local.policies_config : k => config.default_action }
}

# ========================================
# Feature Status per Policy
# ========================================

output "ip_whitelist_status" {
  description = "Map of policy keys to IP whitelist enabled status"
  value       = { for k, v in var.policies : k => v.enable_ip_whitelist }
}

output "ip_blacklist_status" {
  description = "Map of policy keys to IP blacklist enabled status"
  value       = { for k, v in var.policies : k => v.enable_ip_blacklist }
}

# ========================================
# IP Configuration Summary
# ========================================

output "whitelisted_ips" {
  description = "Map of policy keys to their whitelisted IP ranges"
  value       = { for k, v in var.policies : k => v.ip_whitelist }
}

output "blacklisted_ips" {
  description = "Map of policy keys to their blacklisted IP ranges"
  value       = { for k, v in var.policies : k => v.ip_blacklist }
}

output "whitelisted_ip_counts" {
  description = "Map of policy keys to number of whitelisted IP ranges"
  value       = { for k, v in var.policies : k => length(v.ip_whitelist) }
}

output "blacklisted_ip_counts" {
  description = "Map of policy keys to number of blacklisted IP ranges"
  value       = { for k, v in var.policies : k => length(v.ip_blacklist) }
}

# ========================================
# Rule Counts
# ========================================

output "rule_counts" {
  description = "Map of policy keys to total number of IP-based security rules"
  value       = { for k, rules in local.all_rules : k => length(rules) }
}

# ========================================
# Policies Summary (Comprehensive)
# ========================================

output "policies_summary" {
  description = "Comprehensive summary of all security policy configurations"
  value = {
    for k, policy in google_compute_security_policy.policies : k => {
      policy_name    = policy.name
      policy_id      = policy.id
      access_mode    = var.policies[k].access_mode
      default_action = local.policies_config[k].default_action

      features = {
        ip_whitelist = var.policies[k].enable_ip_whitelist
        ip_blacklist = var.policies[k].enable_ip_blacklist
      }

      ip_rules = {
        whitelisted_ips = var.policies[k].ip_whitelist
        blacklisted_ips = var.policies[k].ip_blacklist
        total_rules     = length(local.all_rules[k])
      }

      note = "Advanced WAF features (OWASP, bot protection, rate limiting) are handled by Imperva WAF"
    }
  }
}