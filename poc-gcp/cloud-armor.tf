module "cloud_armor" {
  source = "../modules/cloud-armor"

  project_id = local.project_id
  policies   = local.cloud_armor_policies
}