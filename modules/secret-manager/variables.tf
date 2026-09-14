variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "secrets" {
  description = "Map of secrets to create. Key is used as the internal identifier and must be stable (renaming a key destroys and recreates the secret — blocked by prevent_destroy). Prefer passing secret_data via a data source (e.g. an existing Secret Manager version) or a sensitive variable rather than inline literals; the resource's secret_data attribute is inherently sensitive in state. To use CMEK, set kms_key_name AND provide replication_locations (auto replication does not support CMEK)."
  type = map(object({
    secret_id             = string
    secret_data           = optional(string)
    labels                = optional(map(string), {})
    replication_locations = optional(list(string))
    kms_key_name          = optional(string)
  }))
  default = {}

  # secret_id must match GCP's allowed pattern
  validation {
    condition = alltrue([
      for k, s in var.secrets :
      can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,254}$", s.secret_id))
    ])
    error_message = "secret_id must match ^[a-zA-Z][a-zA-Z0-9_-]{0,254}$ (GCP requirement)."
  }

  # No duplicate replication locations
  validation {
    condition = alltrue([
      for k, s in var.secrets :
      length(coalesce(s.replication_locations, [])) == length(distinct(coalesce(s.replication_locations, [])))
    ])
    error_message = "replication_locations must not contain duplicate locations within a single secret."
  }

  # CMEK requires user-managed replication
  validation {
    condition = alltrue([
      for k, s in var.secrets :
      s.kms_key_name == null || length(coalesce(s.replication_locations, [])) > 0
    ])
    error_message = "kms_key_name (CMEK) requires replication_locations to be set — automatic replication does not support customer-managed encryption keys."
  }

  # kms_key_name must be a full resource path
  validation {
    condition = alltrue([
      for k, s in var.secrets :
      s.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", s.kms_key_name))
    ])
    error_message = "kms_key_name must be a full resource path: projects/<project>/locations/<region>/keyRings/<ring>/cryptoKeys/<key>."
  }

  # Enforce uniqueness of secret_id across all entries in var.secrets.
  validation {
    condition     = length(distinct([for _, s in var.secrets : s.secret_id])) == length(var.secrets)
    error_message = "secret_id values must be unique across all entries in var.secrets. Two map entries cannot share the same secret_id (GCP would reject the second create as a duplicate)."
  }

  # Validate replication_locations contain only valid GCP regions
  validation {
    condition = alltrue([
      for k, s in var.secrets :
      # If replication_locations is provided, it must not be empty (use null for auto-replication)
      (s.replication_locations == null) || length(coalesce(s.replication_locations, [])) > 0
    ])
    error_message = "replication_locations must be null (for automatic replication) or a non-empty list of GCP regions. Empty lists are not allowed — use null instead to enable Google-managed automatic replication."
  }

  # Validate replication_locations contain only valid GCP regions
  validation {
    condition = alltrue([
      for k, s in var.secrets :
      alltrue([
        for location in coalesce(s.replication_locations, []) :
        contains([
          # Americas
          "us-central1", "us-east1",
        ], location)
      ])
    ])
    error_message = "replication_locations must contain only valid GCP region identifiers (e.g., us-central1, europe-west1, asia-east1)."
  }
}