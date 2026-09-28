# ============================================================================
# Core Infrastructure Variables
# ============================================================================

variable "project_id" {
  description = "GCP Project ID where resources will be provisioned"
  type        = string

  validation {
    condition     = length(var.project_id) > 0 && length(var.project_id) <= 30
    error_message = "project_id must be a valid GCP project ID (1-30 characters)."
  }
}

variable "region" {
  description = "Default GCP region used when a cloud_run_service does not explicitly set cloud_run_service_region"
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "region must be a valid GCP region (e.g., us-central1, europe-west1)."
  }
}

# ============================================================================
# Load Balancer Configuration
# ============================================================================

variable "domain_names" {
  description = "List of custom domain names for which Google-managed SSL certificates will be created"
  type        = list(string)

  validation {
    condition     = length(var.domain_names) > 0
    error_message = "domain_names must contain at least one domain."
  }

  validation {
    condition = alltrue([
      for domain in var.domain_names : can(regex("^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)*[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$", domain))
    ])
    error_message = "All domain_names must be valid domain names."
  }
}

variable "ssl_policy_self_link" {
  description = "Optional self_link of an externally managed SSL policy. If null, the module creates a default policy with min TLS 1.2 and MODERN profile."
  type        = string
  default     = null

  validation {
    condition     = var.ssl_policy_self_link == null ? true : length(trimspace(var.ssl_policy_self_link)) > 0
    error_message = "ssl_policy_self_link must be null or a non-empty self_link string."
  }
}

# ============================================================================
# Cloud Run Services Configuration (Multiple Services)
# ============================================================================

variable "cloud_run_services" {
  description = "List of Cloud Run services to route traffic to. Each service can have its own path rules, host rules, security policy, and optional CDN override."
  type = list(object({
    name                     = string           # Identifier for the service (e.g., 'api', 'web')
    cloud_run_service_name   = string           # Name of the Cloud Run service
    cloud_run_service_region = optional(string) # Region where Cloud Run service is deployed (default: var.region)
    security_policy          = string           # Security policy self_link/id attached to this service backend
    cdn_policy = optional(object({
      cache_mode          = string
      default_ttl_seconds = number
      max_ttl_seconds     = number
      client_ttl_seconds  = number
      negative_caching    = bool
      negative_caching_policies = list(object({
        code = number
        ttl  = number
      }))
    }))

    # Routing configuration - at least one must be specified
    path_rules = optional(list(object({
      paths = list(string) # URL paths to route (e.g., ["/api/v1/*", "/api/v1/admin"])
    })), [])

    host_rules = optional(list(object({
      hosts = list(string) # Hostnames to route (e.g., ["api.example.com", "api2.example.com"])
    })), [])
  }))

  validation {
    condition     = length(var.cloud_run_services) > 0
    error_message = "cloud_run_services must contain at least one service."
  }

  validation {
    condition = alltrue([
      for service in var.cloud_run_services :
      length(service.name) > 0 && length(service.name) <= 63
    ])
    error_message = "Each service name must be 1-63 characters."
  }

  validation {
    condition = length(var.cloud_run_services) == length(distinct([
      for service in var.cloud_run_services : trimspace(service.name)
    ]))
    error_message = "Each cloud_run_services[].name must be unique."
  }

  validation {
    condition = alltrue([
      for service in var.cloud_run_services :
      length(service.cloud_run_service_name) > 0 && length(service.cloud_run_service_name) <= 63
    ])
    error_message = "Each cloud_run_service_name must be 1-63 characters."
  }

  validation {
    condition = alltrue([
      for service in var.cloud_run_services :
      length(trimspace(service.security_policy)) > 0
    ])
    error_message = "Each cloud_run_services entry must set a non-empty security_policy."
  }

  validation {
    condition = alltrue([
      for service in var.cloud_run_services :
      service.cloud_run_service_region == null || can(regex("^[a-z]+-[a-z]+[0-9]$", service.cloud_run_service_region))
    ])
    error_message = "Each cloud_run_service_region must be a valid GCP region when set."
  }

  validation {
    condition = alltrue([
      for service in var.cloud_run_services :
      (length(service.path_rules) > 0 || length(service.host_rules) > 0)
    ])
    error_message = "Each service must have at least one path_rule or host_rule."
  }

  validation {
    condition = alltrue(flatten([
      for service in var.cloud_run_services : [
        for rule in service.path_rules :
        length(rule.paths) > 0 && alltrue([for p in rule.paths : length(trimspace(p)) > 0])
      ]
    ]))
    error_message = "Each path_rules entry must contain at least one non-empty path."
  }

  validation {
    condition = alltrue(flatten([
      for service in var.cloud_run_services : [
        for rule in service.host_rules :
        length(rule.hosts) > 0 && alltrue([for h in rule.hosts : length(trimspace(h)) > 0])
      ]
    ]))
    error_message = "Each host_rules entry must contain at least one non-empty host."
  }

  validation {
    condition = length(flatten([
      for service in var.cloud_run_services :
      length(service.host_rules) == 0 ? flatten([for rule in service.path_rules : rule.paths]) : []
      ])) == length(distinct(flatten([
        for service in var.cloud_run_services :
        length(service.host_rules) == 0 ? flatten([for rule in service.path_rules : rule.paths]) : []
    ])))
    error_message = "Path-only services (services without host_rules) must not define duplicate path patterns."
  }

  validation {
    condition = length(flatten([
      for service in var.cloud_run_services : flatten([
        for rule in service.host_rules : [for host in rule.hosts : lower(trimspace(host))]
      ])
      ])) == length(distinct(flatten([
        for service in var.cloud_run_services : flatten([
          for rule in service.host_rules : [for host in rule.hosts : lower(trimspace(host))]
        ])
    ])))
    error_message = "Duplicate hostnames are not allowed across host_rules (comparison is case-insensitive)."
  }

  validation {
    condition = !(
      length(flatten([
        for service in var.cloud_run_services :
        length(service.host_rules) == 0 ? flatten([for rule in service.path_rules : rule.paths]) : []
      ])) > 0 &&
      anytrue(flatten([
        for service in var.cloud_run_services : [
          for rule in service.host_rules : contains([for host in rule.hosts : lower(trimspace(host))], "*")
        ]
      ]))
    )
    error_message = "When path-only services are configured, do not define wildcard host '*' in host_rules; wildcard matching is reserved for the module's global path matcher."
  }

  validation {
    condition = alltrue([
      for service in var.cloud_run_services :
      try(service.cdn_policy.cache_mode, null) == null || contains(["CACHE_ALL_STATIC", "FORCE_CACHE_ALL", "CLIENT_SPECIFIED", "UNSPECIFIED"], try(service.cdn_policy.cache_mode, ""))
    ])
    error_message = "Each cloud_run_services[].cdn_policy.cache_mode must be one of: CACHE_ALL_STATIC, FORCE_CACHE_ALL, CLIENT_SPECIFIED, UNSPECIFIED."
  }

  validation {
    condition = alltrue([
      for service in var.cloud_run_services :
      try(service.cdn_policy.default_ttl_seconds, null) == null || (try(service.cdn_policy.default_ttl_seconds, 0) >= 0 && try(service.cdn_policy.default_ttl_seconds, 0) <= 31536000)
    ])
    error_message = "Each cloud_run_services[].cdn_policy.default_ttl_seconds must be between 0 and 31536000 seconds."
  }

  validation {
    condition = alltrue([
      for service in var.cloud_run_services :
      try(service.cdn_policy.max_ttl_seconds, null) == null || (try(service.cdn_policy.max_ttl_seconds, 0) >= 0 && try(service.cdn_policy.max_ttl_seconds, 0) <= 31536000)
    ])
    error_message = "Each cloud_run_services[].cdn_policy.max_ttl_seconds must be between 0 and 31536000 seconds."
  }

  validation {
    condition = alltrue([
      for service in var.cloud_run_services :
      try(service.cdn_policy.client_ttl_seconds, null) == null || (try(service.cdn_policy.client_ttl_seconds, 0) >= 0 && try(service.cdn_policy.client_ttl_seconds, 0) <= 31536000)
    ])
    error_message = "Each cloud_run_services[].cdn_policy.client_ttl_seconds must be between 0 and 31536000 seconds."
  }

  validation {
    condition = alltrue(flatten([
      for service in var.cloud_run_services : [
        for policy in coalesce(try(service.cdn_policy.negative_caching_policies, null), []) :
        policy.ttl >= 0 && policy.ttl <= 31536000
      ]
    ]))
    error_message = "Each cloud_run_services[].cdn_policy.negative_caching_policies ttl must be between 0 and 31536000 seconds."
  }
}

# ============================================================================
# Cloud CDN Configuration
# ============================================================================

variable "enable_cdn" {
  description = "Enable Cloud CDN for the backend service"
  type        = bool
  default     = true
}

variable "global_default_cdn_policy" {
  description = "Global default Cloud CDN policy map. Per-service cloud_run_services[].cdn_policy can override these values. If this variable is omitted, module defaults are used. When provided, all object attributes must be set. Defaults: cache_mode=CACHE_ALL_STATIC, default_ttl_seconds=3600, max_ttl_seconds=86400, client_ttl_seconds=3600, negative_caching=true, negative policies=[404:120,410:120]."
  type = object({
    cache_mode          = string
    default_ttl_seconds = number
    max_ttl_seconds     = number
    client_ttl_seconds  = number
    negative_caching    = bool
    negative_caching_policies = list(object({
      code = number
      ttl  = number
    }))
  })
  default = {
    cache_mode          = "CACHE_ALL_STATIC"
    default_ttl_seconds = 3600
    max_ttl_seconds     = 86400
    client_ttl_seconds  = 3600
    negative_caching    = true
    negative_caching_policies = [
      { code = 410, ttl = 120 },
      { code = 404, ttl = 120 }
    ]
  }

  validation {
    condition = (
      var.global_default_cdn_policy.cache_mode == null ||
      contains(["CACHE_ALL_STATIC", "FORCE_CACHE_ALL", "CLIENT_SPECIFIED", "UNSPECIFIED"], var.global_default_cdn_policy.cache_mode)
    )
    error_message = "global_default_cdn_policy.cache_mode must be one of: CACHE_ALL_STATIC, FORCE_CACHE_ALL, CLIENT_SPECIFIED, UNSPECIFIED."
  }

  validation {
    condition = (
      var.global_default_cdn_policy.default_ttl_seconds == null ||
      (var.global_default_cdn_policy.default_ttl_seconds >= 0 && var.global_default_cdn_policy.default_ttl_seconds <= 31536000)
    )
    error_message = "global_default_cdn_policy.default_ttl_seconds must be between 0 and 31536000 seconds."
  }

  validation {
    condition = (
      var.global_default_cdn_policy.max_ttl_seconds == null ||
      (var.global_default_cdn_policy.max_ttl_seconds >= 0 && var.global_default_cdn_policy.max_ttl_seconds <= 31536000)
    )
    error_message = "global_default_cdn_policy.max_ttl_seconds must be between 0 and 31536000 seconds."
  }

  validation {
    condition = (
      var.global_default_cdn_policy.client_ttl_seconds == null ||
      (var.global_default_cdn_policy.client_ttl_seconds >= 0 && var.global_default_cdn_policy.client_ttl_seconds <= 31536000)
    )
    error_message = "global_default_cdn_policy.client_ttl_seconds must be between 0 and 31536000 seconds."
  }

  validation {
    condition = alltrue([
      for policy in coalesce(var.global_default_cdn_policy.negative_caching_policies, []) :
      policy.ttl >= 0 && policy.ttl <= 31536000
    ])
    error_message = "Each global_default_cdn_policy.negative_caching_policies ttl must be between 0 and 31536000 seconds."
  }
}

# ============================================================================
# Tagging and Naming
# ============================================================================

variable "labels" {
  description = "Labels to apply to all created resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
  }
}

variable "lb_name_prefix" {
  description = "Prefix for all resource names (e.g., 'myapp-prod'). Must be 1-48 characters."
  type        = string
}

# ============================================================================
# Session Affinity Configuration
# ============================================================================

variable "session_affinity" {
  description = "Type of session affinity to use (NONE, CLIENT_IP, CLIENT_IP_PROTO, CLIENT_IP_PORT)"
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["NONE", "CLIENT_IP", "CLIENT_IP_PROTO", "CLIENT_IP_PORT"], var.session_affinity)
    error_message = "session_affinity must be one of: NONE, CLIENT_IP, CLIENT_IP_PROTO, CLIENT_IP_PORT."
  }
}

# ============================================================================
# Connection Draining Configuration
# ============================================================================

variable "connection_draining_timeout_seconds" {
  description = "Connection draining timeout in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.connection_draining_timeout_seconds > 0 && var.connection_draining_timeout_seconds <= 3600
    error_message = "connection_draining_timeout_seconds must be between 1 and 3600 seconds."
  }
}

# ============================================================================
# Timeout Configuration
# ============================================================================

variable "request_timeout_seconds" {
  description = "Timeout for backend requests in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.request_timeout_seconds > 0 && var.request_timeout_seconds <= 3600
    error_message = "request_timeout_seconds must be between 1 and 3600 seconds."
  }
}

# ============================================================================
# Logging Configuration
# ============================================================================

variable "enable_logging" {
  description = "Enable logging for load balancer backend services"
  type        = bool
  default     = true
}

variable "logging_sample_rate" {
  description = "Logging sample rate (0.0 to 1.0, where 1.0 logs all requests)"
  type        = number
  default     = 1.0

  validation {
    condition     = var.logging_sample_rate >= 0.0 && var.logging_sample_rate <= 1.0
    error_message = "logging_sample_rate must be between 0.0 and 1.0."
  }
}