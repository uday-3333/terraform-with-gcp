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


  # Insert Terraform metadata tags to better track resources managed by Terraform.
  terraform_labels = {
    "poc-terraformworkspace" = terraform.workspace
  }

  # Merge tag maps into common_labels used on all resources
  common_labels = merge(local.terraform_labels, {
    "poc-project" = local.project_name
  })


  # =============================================================
  # Add the naming prefixes for various resources to be created
  # in this project for consistency and to avoid naming conflicts.
  # These prefixes will be used in the resource names..
  # =============================================================
  # Common Naming prefixe for naming resources
  common_name_prefix = "${local.environment}-${local.project_name}"
  # Secret naming prefix for secret manager secrets
  secret_name_prefix = "sms-${local.common_name_prefix}"
  # Bucket naming prefix for storage buckets
  storage_bucket_name_prefix = "gcsbucket-${local.common_name_prefix}"
  # Cloud Run naming prefix for services
  cloud_run_name_prefix = "run-${local.common_name_prefix}"
  # Cloud Armor naming prefix for policies
  cloud_armor_name_prefix = "ca-${local.common_name_prefix}"
  # HTTPS Load Balancer naming prefix
  https_lb_name_prefix = "elb-${local.common_name_prefix}"


  # ========================================================
  # Secret Manager Configuration
  # To add more secrets add to the secrets map below
  # ========================================================
  secrets = {
    smb-oe-app-secrets = {
      secret_id             = "${local.secret_name_prefix}-gcp-poc-app-kv"
      replication_locations = [local.region]
      labels = merge(local.common_labels, {
        name = "${local.secret_name_prefix}-gcp-poc-app-kv"
      })
    }
  }

  # ========================================================
  # Storage Buckets Configuration
  # To add more buckets add to the storage_buckets map below
  # ========================================================
  # Storage buckets - complete configuration
  storage_buckets = {
    "static-config" = {
      name     = "${local.storage_bucket_name_prefix}-static-config"
      location = local.region
      labels = merge(
        local.common_labels,
        {
          name = "${local.storage_bucket_name_prefix}-static-config"
        }
      )
    }
  }

  # ========================================================
  # Cloud Run Services Configurations
  # To add more services add to the cloud_run_services map below
  # ========================================================
  # Cloud Run services - complete configuration
  cloud_run_services = {
    "gcp-poc-app" = {
      service_name             = "${local.cloud_run_name_prefix}-gcp-poc-app"
      service_account_email    = google_service_account.cloud_run_sa.email
      container_image          = "us-docker.pkg.dev/cloudrun/container/hello"
      container_port           = 8080
      startup_probe_enabled    = false
      liveness_probe_enabled   = false
      labels = merge(
        local.common_labels,
        {
          name = "${local.cloud_run_name_prefix}-gcp-poc-app"
        }
      )
    }
  }

  # ========================================================
  # Cloud Armor Configuration - IP Whitelist
  # ========================================================
  # Additional IP addresses to be added to Cloud Armor whitelist
  cloud_armor_additional_allowed_ip_list = [
    # Example IPs (uncomment and replace with actual IPs):
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
      labels = merge(
        local.common_labels,
        {
          name = "${local.cloud_armor_name_prefix}-gcp-poc-policy"
        }
      )
    }
  }

  # ========================================================
  # Cloud HTTPS Load Balancer Services Configurations
  # To add more services add to the cloud_https_lb_configs map below
  # ========================================================
  # Cloud HTTPS Load Balancer services - complete configuration

  cloud_https_lb_configs = {
    "gcp-poc-lb" = {
      domain_names = ["opsnexus.blog"]
      cloud_run_services = [
        {
          name                     = "opsnexus"
          cloud_run_service_name   = module.cloud_run.service_names["gcp-poc-app"]
          cloud_run_service_region = local.region
          security_policy          = module.cloud_armor.policy_ids["allow_corp_and_partners"]
          host_rules = [
            { hosts = ["opsnexus.blog"] }
          ]
        },
      ]

    }
  }
}