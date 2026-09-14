variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "host_project_id" {
  type        = string
  description = "Host project ID for the shared VPC that has SAP connectivity"
  default     = null
}

variable "vpc_network" {
  type        = string
  description = "VPC network name used for SAP connectivity"
  default     = null
}

variable "services" {
  description = "Map of Cloud Run v2 services to deploy. Key is used as the internal identifier and must be stable (renaming a key destroys and recreates the service). Each entry's `service_name` becomes the actual Cloud Run service name in GCP."
  type = map(object({
    service_name    = string
    region          = optional(string, "us-central1")
    container_image = optional(string, "us-docker.pkg.dev/cloudrun/container/hello") // default hello world image if none provided

    # Compute
    cpu_limit                        = optional(string, "1")
    memory_limit                     = optional(string, "1Gi")
    min_instances                    = optional(number, 0)
    max_instances                    = optional(number, 10)
    max_instance_request_concurrency = optional(number, 80)
    timeout_seconds                  = optional(number, 300)
    container_port                   = optional(number, 8080)
    # cpu_throttling maps to v2 template.containers.resources.cpu_idle
    # (true = CPU throttled outside requests — same intent as v1's cpu-throttling=true)
    cpu_throttling    = optional(bool, true)
    startup_cpu_boost = optional(bool, false)

    # Identity
    service_account_email = optional(string)

    # Environment variables
    environment_variables = optional(map(string), {})
    # v2: secret_name -> secret ID in Secret Manager; secret_key -> version
    # (e.g. "latest" or "3"). Names retained for module-caller continuity.
    environment_variables_secret = optional(map(object({
      secret_name = string
      secret_key  = string
    })), {})

    # Volumes
    # v2 secret volume: `secret_name` = Secret Manager secret ID, `secret_key` = version.
    volume_mounts = optional(list(object({
      name       = string
      mount_path = string
    })), [])
    volumes = optional(list(object({
      name        = string
      secret_name = string
      secret_key  = string
      path        = string
    })), [])

    # Ingress and access
    ingress_type  = optional(string, "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER") # "INGRESS_TRAFFIC_ALL" | "INGRESS_TRAFFIC_INTERNAL_ONLY" | "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    default_uri_disabled = optional(bool, true) # Disables the default public URI endpoint

    # # Grant allUsers roles/run.invoker (unauthenticated public access).
    # allow_public_access = optional(bool, false)

    # Annotations and labels
    template_annotations = optional(map(string), {})
    service_annotations  = optional(map(string), {})
    labels               = optional(map(string), {})

    # Runtime
    execution_environment = optional(string, "EXECUTION_ENVIRONMENT_GEN2") # "EXECUTION_ENVIRONMENT_GEN1" | "EXECUTION_ENVIRONMENT_GEN2"
    grpc_enabled          = optional(bool, false)
    session_affinity      = optional(bool, false)

    # VPC
    enable_vpc_egress           = optional(bool, true)
    vpc_subnetwork              = optional(string)
    vpc_egress_type             = optional(string, "ALL_TRAFFIC") # "ALL_TRAFFIC" | "PRIVATE_RANGES_ONLY"

    # Deletion protection (v2 default is true at the API level; module default
    # here is false to match v1 behavior — set true per-env for prod safety).
    deletion_protection = optional(bool, false)

    # Startup probe (initial_delay default is 5s to give containers time to bind
    # their port before the first probe fires — 0 causes needless cold-start failures)
    startup_probe_enabled           = optional(bool, true)
    startup_probe_path              = optional(string, "/")
    startup_probe_initial_delay     = optional(number, 5)
    startup_probe_timeout           = optional(number, 1)
    startup_probe_period            = optional(number, 10)
    startup_probe_failure_threshold = optional(number, 3)

    # Liveness probe
    liveness_probe_enabled           = optional(bool, true)
    liveness_probe_path              = optional(string, "/")
    liveness_probe_initial_delay     = optional(number, 0)
    liveness_probe_timeout           = optional(number, 1)
    liveness_probe_period            = optional(number, 10)
    liveness_probe_failure_threshold = optional(number, 3)

    # Readiness probe
    readiness_probe_enabled           = optional(bool, true)
    readiness_probe_path              = optional(string, "/")
    readiness_probe_timeout           = optional(number, 1)
    readiness_probe_period            = optional(number, 10)
    readiness_probe_failure_threshold = optional(number, 3)

    tags = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, s in var.services :
      contains(["INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"], s.ingress_type)
    ])
    error_message = "ingress_type must be one of: INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }

  validation {
    condition = alltrue([
      for k, s in var.services :
      contains(["EXECUTION_ENVIRONMENT_GEN1", "EXECUTION_ENVIRONMENT_GEN2"], s.execution_environment)
    ])
    error_message = "execution_environment must be either EXECUTION_ENVIRONMENT_GEN1 or EXECUTION_ENVIRONMENT_GEN2."
  }

  validation {
    condition = alltrue([
      for k, s in var.services :
      s.vpc_egress_type == null || contains(["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"], s.vpc_egress_type)
    ])
    error_message = "vpc_egress_type must be either ALL_TRAFFIC or PRIVATE_RANGES_ONLY."
  }

  validation {
    condition = alltrue([
      for k, s in var.services :
      length(setintersection(toset(keys(s.environment_variables)), toset(keys(s.environment_variables_secret)))) == 0
    ])
    error_message = "environment_variables and environment_variables_secret must not share the same keys within a service (Cloud Run rejects duplicate env var names)."
  }

  # Validate service_name format and length (Cloud Run API requirement: 50 char max)
  validation {
    condition = alltrue([
      for k, s in var.services :
      length(s.service_name) <= 50 &&
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$|^[a-z]$", s.service_name))
    ])
    error_message = "service_name must: (1) be 50 characters or less, (2) start with a lowercase letter, (3) contain only lowercase letters, digits, and hyphens, (4) not end with a hyphen. The module will automatically truncate to 50 chars, but providing compliant names is recommended."
  }

  # Force callers to provide a dedicated service account rather than silently
  # falling back to the default compute SA (which has broad project-wide roles).
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.service_account_email != null && trimspace(coalesce(s.service_account_email, "")) != ""
    ])
    error_message = "service_account_email must be set explicitly for every service. Using the default compute service account is a security anti-pattern."
  }

  # Validate env var name format.
  # Cloud Run permits letter-or-underscore start followed by letters, digits,
  # or underscores (case-insensitive). Reserved names starting with X_GOOGLE_
  # are rejected by the platform.
  validation {
    condition = alltrue([
      for k in var.services :
      can(regex("^(0\\.5|1|2|4|6|8)$", k.cpu_limit))
    ])
    error_message = "cpu must be one of: 0.5, 1, 2, 4, 6, 8"
  }

  validation {
    condition = alltrue([
      for k in var.services :
      can(regex("^(128|256|512|1024|2048|4096|8192)Mi|^(0\\.5|1|2|4|8|16|32)Gi$", k.memory_limit))
    ])
    error_message = "memory must include Mi/Gi units"
  }
  validation {
    condition = alltrue([
      for k, s in var.services :
      alltrue([for name in keys(s.environment_variables) : can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", name)) && !startswith(upper(name), "X_GOOGLE_")])
    ])
    error_message = "environment_variables keys must match [a-zA-Z_][a-zA-Z0-9_]* and must not start with 'X_GOOGLE_' (reserved prefix)."
  }

  validation {
    condition = alltrue([
      for k, s in var.services :
      alltrue([for name in keys(s.environment_variables_secret) : can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", name)) && !startswith(upper(name), "X_GOOGLE_")])
    ])
    error_message = "environment_variables_secret keys must match [a-zA-Z_][a-zA-Z0-9_]* and must not start with 'X_GOOGLE_' (reserved prefix)."
  }

  # Validate container_port range
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.container_port >= 1 && s.container_port <= 65535
    ])
    error_message = "container_port must be between 1 and 65535."
  }

  # Cloud Run max request timeout is 3600 seconds (60 minutes)
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.timeout_seconds >= 1 && s.timeout_seconds <= 3600
    ])
    error_message = "timeout_seconds must be between 1 and 3600 (Cloud Run maximum)."
  }

  # Cloud Run instance limits
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.min_instances >= 0 && s.min_instances <= 1000
    ])
    error_message = "min_instances must be between 0 and 1000."
  }

  validation {
    condition = alltrue([
      for k, s in var.services :
      s.max_instances >= 1 && s.max_instances <= 1000
    ])
    error_message = "max_instances must be between 1 and 1000."
  }

  validation {
    condition = alltrue([
      for k, s in var.services :
      s.max_instances >= s.min_instances
    ])
    error_message = "max_instances must be greater than or equal to min_instances."
  }

  # max_instance_request_concurrency: 0 means "unlimited"; otherwise 1-1000
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.max_instance_request_concurrency == 0 || (s.max_instance_request_concurrency >= 1 && s.max_instance_request_concurrency <= 1000)
    ])
    error_message = "max_instance_request_concurrency must be 0 (unlimited) or between 1 and 1000."
  }

  # Cloud Run requires probe period_seconds >= timeout_seconds
  validation {
    condition = alltrue([
      for k, s in var.services :
      !s.startup_probe_enabled || s.startup_probe_period >= s.startup_probe_timeout
    ])
    error_message = "startup_probe_period must be greater than or equal to startup_probe_timeout when startup_probe_enabled = true."
  }

  validation {
    condition = alltrue([
      for k, s in var.services :
      !s.liveness_probe_enabled || s.liveness_probe_period >= s.liveness_probe_timeout
    ])
    error_message = "liveness_probe_period must be greater than or equal to liveness_probe_timeout when liveness_probe_enabled = true."
  }

  validation {
    condition = alltrue([
      for k, s in var.services :
      !s.readiness_probe_enabled || s.readiness_probe_period >= s.readiness_probe_timeout
    ])
    error_message = "readiness_probe_period must be greater than or equal to readiness_probe_timeout when readiness_probe_enabled = true."
  }
}