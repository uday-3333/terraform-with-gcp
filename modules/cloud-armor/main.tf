/**
 * Cloud Armor Security Policy Module - Multiple Policies Support
 * Creates and manages multiple Cloud Armor policies with support for:
 * - IP whitelist (allowlist)
 * - IP blacklist (denylist)
 * - Dynamic private/public access control
 *
 * Note: This module is simplified for IP-based access control only.
 * Advanced WAF features (OWASP rules, bot protection, etc.) are handled by Imperva WAF.
 */

# ========================================
# Local Variables for Each Policy
# ========================================

locals {
  # Calculate base priorities for built-in rules
  base_priority_whitelist = 1000
  base_priority_blacklist = 2000

  # Build configuration for each policy
  policies_config = {
    for key, policy in var.policies : key => {
      name               = policy.name
      description        = policy.description
      is_private_policy  = policy.access_mode == "private"

      # Build IP whitelist rules - chunked into groups of 10 (GCP limit per rule)
      ip_whitelist_rules = policy.enable_ip_whitelist && length(policy.ip_whitelist) > 0 ? [
        for idx, chunk in chunklist(policy.ip_whitelist, 10) : {
          action      = "allow"
          priority    = local.base_priority_whitelist + idx
          description = "Allow whitelisted IP ranges chunk ${idx + 1}"
          match = {
            versioned_expr = "SRC_IPS_V1"
            config = {
              src_ip_ranges = chunk
            }
          }
        }
      ] : []

      # Build IP blacklist rules (optional)
      ip_blacklist_rules = policy.enable_ip_blacklist && length(policy.ip_blacklist) > 0 ? [
        {
          action      = "deny(403)"
          priority    = local.base_priority_blacklist
          description = "Block blacklisted IP ranges (known malicious sources)"
          match = {
            versioned_expr = "SRC_IPS_V1"
            config = {
              src_ip_ranges = policy.ip_blacklist
            }
          }
        }
      ] : []

      # Determine default rule action based on access mode
      default_action = policy.access_mode == "private" ? (
        policy.default_rule_action_override != null ? policy.default_rule_action_override : "deny(403)"
        ) : (
        policy.default_rule_action_override != null ? policy.default_rule_action_override : "allow"
      )

      default_description = policy.access_mode == "private" ? (
        "Default rule - deny all traffic (private mode, explicit IP whitelist required)"
        ) : (
        "Default rule - allow all traffic (public mode, WAF protection via Imperva)"
      )

      log_level               = policy.log_level
      user_ip_request_headers = policy.user_ip_request_headers
      labels                  = policy.labels
    }
  }

  # Combine rules for each policy
  all_rules = {
    for key, config in local.policies_config : key => concat(
      config.ip_whitelist_rules,
      config.ip_blacklist_rules
    )
  }
}

# ========================================
# Security Policies
# ========================================

resource "google_compute_security_policy" "policies" {
  for_each = var.policies

  name    = each.value.name
  project = var.project_id

  description = local.policies_config[each.key].description

  # ========================================
  # Advanced Options - Logging Configuration
  # ========================================
  dynamic "advanced_options_config" {
    for_each = local.policies_config[each.key].log_level != null || local.policies_config[each.key].user_ip_request_headers != null ? [1] : []
    content {
      log_level               = local.policies_config[each.key].log_level
      user_ip_request_headers = local.policies_config[each.key].user_ip_request_headers
    }
  }

  # ========================================
  # IP-based Security Rules (Whitelist/Blacklist)
  # ========================================
  dynamic "rule" {
    for_each = local.all_rules[each.key]
    content {
      action      = rule.value.action
      priority    = rule.value.priority
      description = try(rule.value.description, "")

      # IP-based matching only
      match {
        versioned_expr = rule.value.match.versioned_expr

        config {
          src_ip_ranges = rule.value.match.config.src_ip_ranges
        }
      }
    }
  }

  # ========================================
  # Default Rule (catch-all)
  # Always evaluates last (max priority)
  # Automatically set based on access_mode:
  # - "private" = deny all by default (IP whitelist required)
  # - "public" = allow all by default (Imperva WAF handles security)
  # ========================================
  rule {
    action   = local.policies_config[each.key].default_action
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = local.policies_config[each.key].default_description
  }

  # Lifecycle
  lifecycle {
    create_before_destroy = true
  }
}