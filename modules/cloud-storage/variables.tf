variable "project_id" {
  description = "The ID of the project in which the buckets will be created"
  type        = string
}

variable "buckets" {
  description = "Map of bucket configurations. Key is used as bucket name suffix."
  type = map(object({
    name                  = string
    location              = optional(string, "US")
    storage_class         = optional(string, "STANDARD")
    force_destroy         = optional(bool, false)
    uniform_bucket_level_access = optional(bool, true)
    public_access_prevention    = optional(string, "enforced")
    enable_object_versioning    = optional(bool, true)
    retention_policy = optional(object({
      retention_period = number
      is_locked        = optional(bool, false)
    }))
    lifecycle_rules = optional(list(object({
      action = object({
        type          = string
        storage_class = optional(string)
      })
      condition = object({
        age                        = optional(number)
        created_before             = optional(string)
        with_state                 = optional(string)
        matches_storage_class      = optional(list(string))
        num_newer_versions         = optional(number)
        days_since_noncurrent_time = optional(number)
      })
    })), [])
    kms_key_name = optional(string)
    encryption_key = optional(string)
    logging_config = optional(object({
      log_bucket        = string
      log_object_prefix = optional(string)
    }))
    cors_config = optional(list(object({
      origin          = list(string)
      method          = list(string)
      response_header = optional(list(string))
      max_age_seconds = optional(number)
    })), [])
    website = optional(object({
      main_page_suffix = optional(string)
      not_found_page   = optional(string)
    }))
    labels = optional(map(string), {})
    use_authoritative_policy = optional(bool, false)
    authoritative_policy_bindings = optional(list(object({
      role    = string
      members = list(string)
    })), [])
    enable_auto_deletion = optional(bool, false)
    auto_delete_age_days = optional(number, 90)
    enable_versioning_lifecycle = optional(bool, false)
    noncurrent_version_delete_days = optional(number, 30)
  }))
  default = {}
}