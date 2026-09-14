resource "google_storage_bucket" "buckets" {
  for_each = var.buckets

  name          = each.value.name
  project       = var.project_id
  location      = each.value.location
  storage_class = each.value.storage_class
  force_destroy = each.value.force_destroy

  # Security: Uniform bucket-level access (disables ACLs, uses IAM only)
  uniform_bucket_level_access = each.value.uniform_bucket_level_access

  # Security: Public access prevention (enforced by default for security)
  public_access_prevention = each.value.public_access_prevention

  # Security: Object versioning for data protection
  dynamic "versioning" {
    for_each = each.value.enable_object_versioning ? [1] : []
    content {
      enabled = true
    }
  }

  # Security: Retention policy for compliance
  dynamic "retention_policy" {
    for_each = each.value.retention_policy != null ? [each.value.retention_policy] : []
    content {
      retention_period = retention_policy.value.retention_period
      is_locked        = retention_policy.value.is_locked
    }
  }

  # Lifecycle rules from variable
  dynamic "lifecycle_rule" {
    for_each = each.value.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = try(lifecycle_rule.value.action.storage_class, null)
      }

      condition {
        age                        = try(lifecycle_rule.value.condition.age, null)
        created_before             = try(lifecycle_rule.value.condition.created_before, null)
        with_state                 = try(lifecycle_rule.value.condition.with_state, null)
        matches_storage_class      = try(lifecycle_rule.value.condition.matches_storage_class, null)
        num_newer_versions         = try(lifecycle_rule.value.condition.num_newer_versions, null)
        days_since_noncurrent_time = try(lifecycle_rule.value.condition.days_since_noncurrent_time, null)
      }
    }
  }

  # Auto-deletion lifecycle rule
  dynamic "lifecycle_rule" {
    for_each = each.value.enable_auto_deletion ? [1] : []
    content {
      action {
        type = "Delete"
      }
      condition {
        age = each.value.auto_delete_age_days
      }
    }
  }

  # Versioning lifecycle rule - delete old versions
  dynamic "lifecycle_rule" {
    for_each = each.value.enable_versioning_lifecycle ? [1] : []
    content {
      action {
        type = "Delete"
      }
      condition {
        days_since_noncurrent_time = each.value.noncurrent_version_delete_days
        with_state                 = "ARCHIVED"
      }
    }
  }

  # Security: Customer-managed encryption keys (CMEK)
  dynamic "encryption" {
    for_each = each.value.kms_key_name != null || each.value.encryption_key != null ? [1] : []
    content {
      default_kms_key_name = coalesce(each.value.kms_key_name, each.value.encryption_key)
    }
  }

  dynamic "logging" {
    for_each = each.value.logging_config != null ? [1] : []
    content {
      log_bucket        = each.value.logging_config.log_bucket
      log_object_prefix = try(each.value.logging_config.log_object_prefix, null)
    }
  }

  dynamic "cors" {
    for_each = each.value.cors_config
    content {
      origin          = cors.value.origin
      method          = cors.value.method
      response_header = try(cors.value.response_header, null)
      max_age_seconds = try(cors.value.max_age_seconds, null)
    }
  }

  dynamic "website" {
    for_each = each.value.website != null ? [each.value.website] : []
    content {
      main_page_suffix = try(website.value.main_page_suffix, null)
      not_found_page   = try(website.value.not_found_page, null)
    }
  }

  labels = each.value.labels
}

# Authoritative IAM Policy (when use_authoritative_policy is true)
data "google_iam_policy" "authoritative_policy" {
  for_each = { for k, v in var.buckets : k => v if v.use_authoritative_policy }

  dynamic "binding" {
    for_each = each.value.authoritative_policy_bindings
    content {
      role    = binding.value.role
      members = binding.value.members
    }
  }
}

resource "google_storage_bucket_iam_policy" "policy" {
  for_each = { for k, v in var.buckets : k => v if v.use_authoritative_policy }

  bucket      = google_storage_bucket.buckets[each.key].name
  policy_data = data.google_iam_policy.authoritative_policy[each.key].policy_data
}