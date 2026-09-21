locals {
  # ================================================================
  # SITES — operator interface
  # This is the ONLY file you need to edit to add or modify a site.
  # All Cloud Run, LB, storage, and extension configs are derived
  # automatically from this map in locals.tf.
  #
  # lb_key        — stable key used in LB resource names (never change after creation)
  # cloud_run_key — stable key used in Cloud Run resource names (never change after creation)
  # ================================================================
  sites = {
    "opsnexus" = {
      domain             = "opsnexus.blog"
      lb_key             = "gcp-poc-lb"       # preserves existing LB resource names
      cloud_run_key      = "gcp-poc-app"      # preserves existing Cloud Run resource names
      cloud_run_image    = "us-docker.pkg.dev/cloudrun/container/hello"
      container_port     = 8080
      armor_policy_key   = "allow_corp_and_partners"
      maintenance_mode   = false     # flip to true to activate maintenance page
      enable_extension   = true  # flip to true to activate Option B (Service Extension)
      admin_bypass_cidrs = []     # CIDRs that always bypass maintenance e.g. ["203.0.113.10/32"]
      test_tenant_host   = ""     # host header that always bypasses maintenance

      # Path redirects: redirect from_paths to a new path or host (no backend needed)
      # response_code: MOVED_PERMANENTLY_DEFAULT (301), FOUND (302), TEMPORARY_REDIRECT (307), PERMANENT_REDIRECT (308)
      redirects = [
        # Vanity path redirects — exact path matches (static, no Cloud Run callout needed)
        { from_paths = ["/PROMO2026"],    to_host = "www.opsnexus.blog", to_path = "/promotions/spring-2026",          response_code = "MOVED_PERMANENTLY_DEFAULT" },
        { from_paths = ["/ABOUTCARE"],    to_host = "www.opsnexus.blog", to_path = "/en/public/reliant_care.jsp",       response_code = "MOVED_PERMANENTLY_DEFAULT" },
        { from_paths = ["/ACCOUNTTOOLS"], to_host = "www.opsnexus.blog", to_path = "/en/residential/customer-care/",   response_code = "MOVED_PERMANENTLY_DEFAULT" },
        # Legacy path redirect
        { from_paths = ["/old", "/old/*"], to_path = "/new", response_code = "MOVED_PERMANENTLY_DEFAULT" },
      ]

      # Vanity domains: extra hostnames served by this site's LB
      # redirect_to: 301 redirect to another host (e.g. www → apex)
      # cloud_run_key: serve same or different Cloud Run app on this vanity host
      vanity_domains = [
        # www → apex redirect
        { domain = "www.opsnexus.blog", redirect_to = "opsnexus.blog" },
      ]
    }

    # ----------------------------------------------------------------
    # To add a new site, copy the block below, uncomment, and fill in:
    # ----------------------------------------------------------------
    # "site2" = {
    #   domain             = "site2.example.com"
    #   lb_key             = "site2-lb"
    #   cloud_run_key      = "site2-app"
    #   cloud_run_image    = "us-docker.pkg.dev/cloudrun/container/hello"
    #   container_port     = 8080
    #   armor_policy_key   = "allow_corp_and_partners"
    #   maintenance_mode   = true
    #   enable_extension   = false
    #   admin_bypass_cidrs = []
    #   test_tenant_host   = ""
    #   redirects          = []
    #   vanity_domains     = []
    # }
  }
}