# Combined per-service map
output "services" {
  description = "Map of service key to service details. v2 flattens status into top-level attributes: `uri` replaces v1's status[0].url."
  value = {
    for k, s in google_cloud_run_v2_service.service : k => {
      id                      = s.id
      name                    = s.name
      location                = s.location
      uri                     = s.uri
      urls                    = s.urls
      latest_ready_revision   = s.latest_ready_revision
      latest_created_revision = s.latest_created_revision
      generation              = s.generation
      observed_generation     = s.observed_generation
   }
  }
}

# Individual attribute maps
output "service_ids" {
  description = "Map of service key to Cloud Run service ID"
  value       = { for k, s in google_cloud_run_v2_service.service : k => s.id }
}

output "service_names" {
  description = "Map of service key to Cloud Run service name"
  value       = { for k, s in google_cloud_run_v2_service.service : k => s.name }
}

output "service_uris" {
  description = "Map of service key to Cloud Run service primary URI (v2 top-level `uri`)."
  value       = { for k, s in google_cloud_run_v2_service.service : k => s.uri }
}

output "service_locations" {
  description = "Map of service key to Cloud Run service location"
  value       = { for k, s in google_cloud_run_v2_service.service : k => s.location }
}

# output "public_access_services" {
#   description = "Map of service key to allUsers IAM binding etag for services with allow_public_access = true (empty if none)."
#   value       = { for k, m in google_cloud_run_v2_service_iam_member.public_access : k => m.etag }
# }