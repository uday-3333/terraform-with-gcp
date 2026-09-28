locals {
  # ================================================================
  # SITES — operator interface
  # This is the ONLY file you need to edit to add or modify a site.
  # All Cloud Run, LB, storage, and extension configs are derived
  # automatically from this map in locals.tf.
  #
  # lb_key        — stable key used in LB resource names (never change after creation)
  # cloud_run_key — stable key used in Cloud Run resource names (never change after creation)
  #
  # Maintenance, redirects, vanities, and HTTP headers are managed at runtime
  # via GCS: gs://<static-config-bucket>/maintenance/
  #   maintenance.json  — {"maintenance": "on|off"}
  #   redirects.json    — [{"source": "^/old.*$", "destination": "https://..."}]
  #   vanities.json     — [{"source": "/PROMO2026", "destination": "https://..."}]
  #   maintenance.html  — HTML page shown during maintenance
  #   http_headers.json — [{"headerKey": "x-frame-options", "headerValue": "SAMEORIGIN"}]
  # ================================================================
  sites = {
    "opsnexus" = {
      domain           = "opsnexus.blog"
      lb_key           = "gcp-poc-lb"   # preserves existing LB resource names
      cloud_run_key    = "gcp-poc-app"  # preserves existing Cloud Run resource names
      cloud_run_image  = "us-docker.pkg.dev/cloudrun/container/hello"
      container_port   = 8080
      armor_policy_key = "allow_corp_and_partners"
      enable_extension = true
    }

    # ----------------------------------------------------------------
    # To add a new site, copy the block below, uncomment, and fill in:
    # ----------------------------------------------------------------
    # "site2" = {
    #   domain           = "site2.example.com"
    #   lb_key           = "site2-lb"
    #   cloud_run_key    = "site2-app"
    #   cloud_run_image  = "us-docker.pkg.dev/cloudrun/container/hello"
    #   container_port   = 8080
    #   armor_policy_key = "allow_corp_and_partners"
    #   enable_extension = false
    # }
  }
}