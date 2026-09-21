module "storage_buckets" {
  source     = "../modules/cloud-storage"
  project_id = local.project_id
  buckets    = local.storage_buckets
}

# ============================================================================
# Ops-config objects — maintenance/ folder inside static-config bucket
# ============================================================================
# These files are read by the decision Cloud Run callout service (5s TTL cache).
# App teams update these files directly (no Terraform apply needed) to toggle
# maintenance mode, add redirects, or add vanity URL mappings at runtime.
#
# maintenance/maintenance.json  ← set {"maintenance":"on"} to enable maintenance mode
# maintenance/redirects.json    ← regex-based redirect rules (requires callout service)
# maintenance/vanities.json     ← exact-path vanity URL mappings (requires callout service)
# maintenance/maintenance.html  ← HTML page served to users during maintenance

resource "google_storage_bucket_object" "maintenance_config" {
  name         = "maintenance/maintenance.json"
  bucket       = module.storage_buckets.bucket_names["static-config"]
  content_type = "application/json"
  content      = jsonencode({ maintenance = "off" })
}

resource "google_storage_bucket_object" "redirects_config" {
  name         = "maintenance/redirects.json"
  bucket       = module.storage_buckets.bucket_names["static-config"]
  content_type = "application/json"
  # Format: [{"source": "^/files.*$", "destination": "https://example.com"}]
  content = jsonencode([])
}

resource "google_storage_bucket_object" "vanities_config" {
  name         = "maintenance/vanities.json"
  bucket       = module.storage_buckets.bucket_names["static-config"]
  content_type = "application/json"
  # Format: [{"source": "/PROMO2026", "destination": "https://example.com/promo"}]
  content = jsonencode([])
}

resource "google_storage_bucket_object" "maintenance_html" {
  name         = "maintenance/maintenance.html"
  bucket       = module.storage_buckets.bucket_names["static-config"]
  content_type = "text/html"
  content      = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head><meta charset="UTF-8"><title>Maintenance</title>
    <style>body{font-family:sans-serif;text-align:center;padding:80px;background:#f5f5f5}
    h1{color:#333}p{color:#666}</style></head>
    <body><h1>Scheduled Maintenance</h1>
    <p>We are currently performing scheduled maintenance. Please check back shortly.</p>
    </body></html>
  HTML
}

# index.html served to users by the GCS backend bucket during maintenance (one per site)
resource "google_storage_bucket_object" "maintenance_index_html" {
  for_each = { for k, s in local.sites : k => s }

  name         = "index.html"
  bucket       = module.storage_buckets.bucket_names["${each.value.lb_key}-maintenance"]
  content_type = "text/html"
  content      = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head><meta charset="UTF-8"><title>Maintenance</title>
    <style>body{font-family:sans-serif;text-align:center;padding:80px;background:#f5f5f5}
    h1{color:#333}p{color:#666}</style></head>
    <body><h1>Scheduled Maintenance</h1>
    <p>We are currently performing scheduled maintenance. Please check back shortly.</p>
    </body></html>
  HTML
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
