locals {
  cloud_run_services_resolved = {
    for k, v in local.cloud_run_services : k => merge(v, {
      vpc_subnetwork = google_compute_subnetwork.subnet_private.name
    })
  }
}

module "cloud_run" {
  source = "../modules/cloud-run"

  project_id      = local.project_id
  host_project_id = local.host_project_id
  vpc_network     = local.vpc_network

  services = local.cloud_run_services_resolved
}