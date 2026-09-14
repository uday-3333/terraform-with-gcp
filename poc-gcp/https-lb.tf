module "cloud_https_lbs" {
  source = "../modules/https-lb"
  for_each = local.cloud_https_lb_configs

  project_id     = local.project_id
  lb_name_prefix = "${local.https_lb_name_prefix}-${each.key}"
  domain_names   = each.value.domain_names
  enable_cdn     = true

  cloud_run_services = each.value.cloud_run_services
}