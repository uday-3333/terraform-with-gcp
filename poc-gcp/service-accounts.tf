# Cloud Run Service Account
resource "google_service_account" "cloud_run_sa" {
  account_id   = "poc-cloud-run-sa"
  display_name = "Cloud Run Service Account for POC"
  project      = local.project_id

  description = "Service account for Cloud Run services in ${local.environment} environment"
}

# Allow unauthenticated public access to Cloud Run services
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  for_each = local.cloud_run_services

  project  = local.project_id
  location = local.region
  name     = each.value.service_name
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [module.cloud_run]
}

# Assign necessary roles to Cloud Run service account
resource "google_project_iam_member" "cloud_run_roles" {
  for_each = toset([
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
  ])

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}