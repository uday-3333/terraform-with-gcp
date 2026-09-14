# ==========================================
# SECRET MANAGER MODULE
# ==========================================
# Creates and manages one or more secrets in Google Secret Manager.
# Each entry in var.secrets is an independent secret; its key is used
# as a stable identifier for state addressing.
#
# IMPORTANT: `prevent_destroy = true` is hard-coded on the secret resource.
# To remove a secret entirely, first `terraform state rm` the secret,
# then delete the key from var.secrets. This is intentional — accidental
# secret deletion is not recoverable.
#
# CMEK: to encrypt a secret with a customer-managed key, set kms_key_name
# on the secret AND provide replication_locations (auto replication does
# not support CMEK — enforced by validation).

locals {
  # Secrets that should be seeded with an initial version at creation time
  secrets_with_data = {
    for k, s in var.secrets : k => s if s.secret_data != null
  }
}

# Create Secret
resource "google_secret_manager_secret" "secret" {
  for_each = var.secrets

  secret_id = each.value.secret_id
  project   = var.project_id
  labels    = each.value.labels

  # Use user-managed replication only when a non-empty list of locations is provided;
  # otherwise fall back to automatic replication. This prevents an invalid empty
  # user_managed block when replication_locations = []. Empty lists are not allowed by validation.
  # Set replication_locations = null (or omit it) to use automatic replication (Google-managed).
  dynamic "replication" {
    for_each = each.value.replication_locations != null && length(coalesce(each.value.replication_locations, [])) > 0 ? [1] : []
    content {
      user_managed {
        dynamic "replicas" {
          for_each = each.value.replication_locations
          content {
            location = replicas.value

            dynamic "customer_managed_encryption" {
              for_each = each.value.kms_key_name != null ? [1] : []
              content {
                kms_key_name = each.value.kms_key_name
              }
            }
          }
        }
      }
    }
  }

  dynamic "replication" {
    for_each = each.value.replication_locations == null || length(coalesce(each.value.replication_locations, [])) == 0 ? [1] : []
    content {
      auto {}
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Create Secret Version (with initial value)
resource "google_secret_manager_secret_version" "secret_version" {
  for_each = local.secrets_with_data

  secret      = google_secret_manager_secret.secret[each.key].id
  secret_data = each.value.secret_data

  lifecycle {
    ignore_changes = [secret_data] # Rotation happens out-of-band via gcloud
  }
}