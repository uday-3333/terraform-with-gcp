# Combined per-secret map
output "secrets" {
  description = "Map of secret key to all secret details. version fields are null unless the secret was seeded with secret_data at creation time."
  value = {
    for k, s in google_secret_manager_secret.secret : k => {
      id                = s.id
      secret_id         = s.secret_id
      name              = s.name
      initial_version   = try(google_secret_manager_secret_version.secret_version[k].version, null)
      initial_version_name = try(google_secret_manager_secret_version.secret_version[k].name, null)
    }
  }
  sensitive = true
}

# Individual attribute maps
output "secret_ids" {
  description = "Map of secret key to short secret ID"
  value       = { for k, s in google_secret_manager_secret.secret : k => s.secret_id }
}

output "secret_names" {
  description = "Map of secret key to full resource name of the secret"
  value       = { for k, s in google_secret_manager_secret.secret : k => s.name }
}

output "secret_versions" {
  description = "Map of secret key to the initial version number as returned by the provider (only for secrets seeded with secret_data at creation time). NOTE: this always reflects the INITIAL version because secret_data changes are ignored — later rotations via gcloud are not tracked here. Consumers should reference secrets via the 'latest' alias."
  value       = { for k, v in google_secret_manager_secret_version.secret_version : k => v.version }
  sensitive   = true
}

output "secret_version_names" {
  description = "Map of secret key to full resource name of the initial secret version (only for secrets seeded with secret_data at creation time)."
  value       = { for k, v in google_secret_manager_secret_version.secret_version : k => v.name }
  sensitive   = true
}