locals {
  # ========================================
  # Project Configuration
  # ========================================
  project_id      = "project-19604615-6ee6-45bb-b61"
  host_project_id = "project-19604615-6ee6-45bb-b61"
  region          = "us-central1"
  environment     = "dev"
  project_name    = "project-gcp-poc-dev"
  project_display = "poc-dev"
  vpc_network     = "poc-net-${local.environment}-vpc-sharedvpc-001"

  terraform_labels = { "poc-terraformworkspace" = terraform.workspace }
  common_labels    = merge(local.terraform_labels, { "poc-project" = local.project_name })

  common_name_prefix         = "${local.environment}-${local.project_name}"
  secret_name_prefix         = "sms-${local.common_name_prefix}"
  storage_bucket_name_prefix = "gcsbucket-${local.common_name_prefix}"
  cloud_run_name_prefix      = "run-${local.common_name_prefix}"
  cloud_armor_name_prefix    = "ca-${local.common_name_prefix}"
  https_lb_name_prefix       = "elb-${local.common_name_prefix}"

  # ========================================
  # Secret Manager Configuration
  # ========================================
  secrets = {
    smb-oe-app-secrets = {
      secret_id             = "${local.secret_name_prefix}-gcp-poc-app-kv"
      replication_locations = [local.region]
      labels                = merge(local.common_labels, { name = "${local.secret_name_prefix}-gcp-poc-app-kv" })
    }
  }

  # ========================================
  # Cloud Armor — shared policy
  # Sites reference a policy by key via armor_policy_key in sites.tf
  # ========================================
  cloud_armor_additional_allowed_ip_list = [
    # "203.0.113.0/24",
    # "198.51.100.50/32",
  ]

  cloud_armor_policies = {
    "allow_corp_and_partners" = {
      name                = "${local.cloud_armor_name_prefix}-gcp-poc-policy"
      description         = "Cloud Armor policy for ${local.environment} environment - IP whitelist only"
      access_mode         = "public"
      enable_ip_whitelist = true
      ip_whitelist        = local.cloud_armor_additional_allowed_ip_list
      log_level           = "NORMAL"
      labels              = merge(local.common_labels, { name = "${local.cloud_armor_name_prefix}-gcp-poc-policy" })
    }
  }

  # ========================================
  # Derived: Cloud Run services (one per site)
  # ========================================
  cloud_run_services = {
    for site_key, site in local.sites :
    site.cloud_run_key => {
      service_name           = "${local.cloud_run_name_prefix}-${site.cloud_run_key}"
      service_account_email  = google_service_account.cloud_run_sa.email
      container_image        = site.cloud_run_image
      container_port         = site.container_port
      startup_probe_enabled  = false
      liveness_probe_enabled = false
      labels                 = merge(local.common_labels, { name = "${local.cloud_run_name_prefix}-${site.cloud_run_key}" })
    }
  }

  # ========================================
  # Derived: Storage buckets
  # static-config always exists.
  # A maintenance bucket is created per site only when maintenance_mode = true.
  # ========================================
  storage_buckets = merge(
    {
      "static-config" = {
        name     = "${local.storage_bucket_name_prefix}-static-config"
        location = local.region
        labels   = merge(local.common_labels, { name = "${local.storage_bucket_name_prefix}-static-config" })
      }
    },
    {
      for site_key, site in local.sites :
      "${site.lb_key}-maintenance" => {
        name                        = "${local.storage_bucket_name_prefix}-${site.lb_key}-maintenance"
        location                    = local.region
        public_access_prevention    = "inherited"
        uniform_bucket_level_access = true
        enable_object_versioning    = false
        website                     = { main_page_suffix = "index.html" }
        labels                      = merge(local.common_labels, { name = "${local.storage_bucket_name_prefix}-${site.lb_key}-maintenance" })
        use_authoritative_policy    = true
        authoritative_policy_bindings = [
          { role = "roles/storage.objectViewer", members = ["allUsers"] }
        ]
      }
      if site.maintenance_mode
    }
  )

  # ========================================
  # Derived: HTTPS LB configs (one LB per site)
  # ========================================
  cloud_https_lb_configs = {
    for site_key, site in local.sites :
    "${site.lb_key}" => {
      domain_names     = [site.domain]
      maintenance_mode = site.maintenance_mode
      healthz_paths    = ["/healthz", "/healthz/*"]
      api_paths        = ["/api", "/api/*"]

      cloud_run_services = [
        {
          name                     = site_key
          cloud_run_service_name   = module.cloud_run.service_names[site.cloud_run_key]
          cloud_run_service_region = local.region
          security_policy          = module.cloud_armor.policy_ids[site.armor_policy_key]
          host_rules               = [{ hosts = [site.domain] }]
        }
      ]

      gcs_backends = site.maintenance_mode ? [
        {
          name        = "${site.lb_key}-maintenance"
          bucket_name = module.storage_buckets.bucket_names["${site.lb_key}-maintenance"]
          enable_cdn  = false
          path_rules  = [{ paths = ["/*", "/"] }]
        }
      ] : []
    }
  }
}
