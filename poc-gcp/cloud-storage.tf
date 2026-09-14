module "storage_buckets" {
  source = "../modules/cloud-storage"

  project_id = local.project_id
  buckets    = local.storage_buckets
}