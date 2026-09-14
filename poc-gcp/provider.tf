terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.38.0"
    }
  }
}

provider "google" {
  project = local.project_id
  region  = local.region
}