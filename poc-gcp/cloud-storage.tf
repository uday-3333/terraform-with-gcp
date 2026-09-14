module "storage_buckets" {
  source     = "../modules/cloud-storage"
  project_id = local.project_id
  buckets    = local.storage_buckets
}

# api-503.json served to API clients during maintenance (one per site, only when maintenance_mode = true)
resource "google_storage_bucket_object" "api_503" {
  for_each = { for k, s in local.sites : k => s if s.maintenance_mode }

  name         = "api-503.json"
  bucket       = module.storage_buckets.bucket_names["${each.value.lb_key}-maintenance"]
  content_type = "application/json"
  content = jsonencode({
    error   = "service_unavailable"
    message = "The service is temporarily unavailable for maintenance. Please try again later."
    code    = 503
  })
}
