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
# maintenance/http_headers.json ← security response headers injected on every response

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

resource "google_storage_bucket_object" "http_headers_config" {
  name         = "maintenance/http_headers.json"
  bucket       = module.storage_buckets.bucket_names["static-config"]
  content_type = "application/json"
  # Format: [{"headerKey": "x-frame-options", "headerValue": "SAMEORIGIN"}]
  source = "${path.module}/../callout-service/http_headers.json"
}


