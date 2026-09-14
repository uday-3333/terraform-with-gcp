/**
 * Variables for Cloud Armor Security Policy Module - Multiple Policies Support
 * This module focuses on IP-based access control for multiple policies.
 * Advanced WAF features (OWASP, bot protection, rate limiting) are handled by Imperva WAF.
 */

# ========================================
# General Configuration
# ========================================

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "policies" {
  description = "Map of Cloud Armor security policies. Key is used as policy identifier."
  type = map(object({
    name        = string
    description = optional(string, "Cloud Armor IP-based Access Control Policy (WAF via Imperva)")
    access_mode = optional(string, "public")

    # IP Whitelist Configuration
    enable_ip_whitelist = optional(bool, false)
    ip_whitelist        = optional(list(string), [])

    # IP Blacklist Configuration (Optional)
    enable_ip_blacklist = optional(bool, false)
    ip_blacklist        = optional(list(string), [])

    # Default Rule Override
    default_rule_action_override = optional(string)

    # Advanced Options - Logging
    log_level               = optional(string, "NORMAL")
    user_ip_request_headers = optional(list(string))

    # Labels
    labels = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.policies : can(regex("^[a-z](?:[-a-z0-9]{0,61}[a-z0-9])?$", v.name))
    ])
    error_message = "All policy names must be 1-63 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }

  validation {
    condition = alltrue([
      for k, v in var.policies : contains(["private", "public"], v.access_mode)
    ])
    error_message = "access_mode must be either 'private' or 'public' for all policies."
  }

  validation {
    condition = alltrue([
      for k, v in var.policies : contains(["NORMAL", "VERBOSE"], v.log_level)
    ])
    error_message = "log_level must be NORMAL or VERBOSE for all policies."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.policies : [
        for ip in v.ip_whitelist : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?$", ip))
      ]
    ]))
    error_message = "All IP whitelist entries must be valid CIDR notation (e.g., 192.168.1.0/24 or 10.0.0.1/32)."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.policies : [
        for ip in v.ip_blacklist : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?$", ip))
      ]
    ]))
    error_message = "All IP blacklist entries must be valid CIDR notation (e.g., 192.168.1.0/24 or 10.0.0.1/32)."
  }
}