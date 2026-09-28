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
  # Decision callout services are added for sites with enable_extension = true.
  # The decision service implements the Envoy External Processing gRPC API,
  # reads ops-config from GCS (maintenance/, redirects/, vanities/ prefixes
  # inside the static-config bucket) and returns routing decisions to the LB.
  # ========================================
  cloud_run_services = merge(
    {
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
    },
    # Decision callout service — one per extension-enabled site
    # Replace container_image with your real gRPC callout image before enabling.
    {
      for site_key, site in local.sites :
      "${site_key}-decision" => {
        service_name          = "${local.cloud_run_name_prefix}-${site_key}-decision"
        service_account_email = google_service_account.cloud_run_sa.email
        # Image built by Cloud Build — pinned to immutable digest for reproducible deployments.
        # To rebuild: gcloud builds submit --config callout-service/cloudbuild.yaml callout-service/
        container_image       = "gcr.io/project-19604615-6ee6-45bb-b61/maintenance-callout@sha256:10cd0b6f5428db6fb64c99f9f0a3c646d24166190b2427f90f1f694f6cf61fec"
        container_port        = 8080
        grpc_enabled          = true   # sets port name to h2c (HTTP/2 cleartext) for gRPC
        cpu_throttling        = false  # always-on CPU for consistent low latency
        min_instances         = 2      # keep warm — cold starts add latency to every request
        max_instances         = 20
        startup_probe_enabled           = false
        liveness_probe_enabled          = false
        readiness_probe_enabled         = false
        startup_probe_initial_delay     = 0
        startup_probe_timeout           = 1
        startup_probe_period            = 10
        startup_probe_failure_threshold = 3
        environment_variables = {
          GCS_BUCKET         = "${local.storage_bucket_name_prefix}-static-config"
          GCS_FOLDER_PREFIX  = "maintenance"
          CONFIG_TTL_SECONDS = "5"
        }
        labels = merge(local.common_labels, { name = "${local.cloud_run_name_prefix}-${site_key}-decision" })
      }
      if site.enable_extension
    }
  )

  # ========================================
  # Derived: Storage buckets
  # static-config holds all ops-config files read by the callout service:
  #   maintenance/maintenance.json, redirects.json, vanities.json,
  #   maintenance.html, http_headers.json
  # ========================================
  storage_buckets = {
    "static-config" = {
      name          = "${local.storage_bucket_name_prefix}-static-config"
      location      = local.region
      force_destroy = true
      labels        = merge(local.common_labels, { name = "${local.storage_bucket_name_prefix}-static-config" })
    }
  }

  # ========================================
  # Derived: HTTPS LB configs (one LB per site)
  # Maintenance, redirects, vanities, and HTTP headers are handled at runtime
  # by the callout service reading GCS config — no LB-level config needed.
  # ========================================
  cloud_https_lb_configs = {
    for site_key, site in local.sites :
    "${site.lb_key}" => {
      domain_names = [site.domain]

      cloud_run_services = [
        {
          name                     = site_key
          cloud_run_service_name   = module.cloud_run.service_names[site.cloud_run_key]
          cloud_run_service_region = local.region
          security_policy          = module.cloud_armor.policy_ids[site.armor_policy_key]
          host_rules               = [{ hosts = [site.domain] }]
        }
      ]
    }
  }
}
