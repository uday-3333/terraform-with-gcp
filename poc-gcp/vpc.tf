# ========================================================
# VPC Network Configuration for GCP POC
# ========================================================

# Create the VPC Network
resource "google_compute_network" "vpc_network" {
  name                    = "poc-net-${local.environment}-vpc-sharedvpc-001"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  project                 = local.project_id
}

# ========================================================
# Subnet 1: Private Subnet for Cloud Run and Services
# ========================================================
resource "google_compute_subnetwork" "subnet_private" {
  name          = "poc-net-${local.environment}-sbn-001"
  ip_cidr_range = "10.0.1.0/24"
  region        = local.region
  network       = google_compute_network.vpc_network.id
  project       = local.project_id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  depends_on = [google_compute_network.vpc_network]
}



# ========================================================
# Subnet 2: Secondary Subnet for Database and Data Services
# ========================================================
resource "google_compute_subnetwork" "subnet_data" {
  name          = "poc-net-${local.environment}-sbn-002"
  ip_cidr_range = "10.0.2.0/24"
  region        = local.region
  network       = google_compute_network.vpc_network.id
  project       = local.project_id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  depends_on = [google_compute_network.vpc_network]
}

# ========================================================
# Cloud NAT for Private Subnets Outbound Internet Access
# ========================================================
resource "google_compute_router" "nat_router" {
  name    = "poc-net-${local.environment}-rtr-nat"
  region  = local.region
  network = google_compute_network.vpc_network.id
  project = local.project_id

  depends_on = [google_compute_network.vpc_network]
}

resource "google_compute_router_nat" "nat_gateway" {
  name                               = "poc-nat-${local.environment}"
  router                             = google_compute_router.nat_router.name
  region                             = google_compute_router.nat_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  depends_on = [google_compute_router.nat_router]
}

# ========================================================
# Firewall Rules
# ========================================================

# Allow internal communication within VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "poc-net-${local.environment}-fw-allow-internal"
  network = google_compute_network.vpc_network.name
  project = local.project_id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    google_compute_subnetwork.subnet_private.ip_cidr_range,
    google_compute_subnetwork.subnet_data.ip_cidr_range,
  ]

  depends_on = [
    google_compute_subnetwork.subnet_private,
    google_compute_subnetwork.subnet_data,
  ]
}

# Allow Cloud Run to Health Checks (required for load balancing)
resource "google_compute_firewall" "allow_health_checks" {
  name    = "poc-net-${local.environment}-fw-allow-health-checks"
  network = google_compute_network.vpc_network.name
  project = local.project_id

  allow {
    protocol = "tcp"
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
  ]

  depends_on = [google_compute_network.vpc_network]
}

# ========================================================
# VPC Peering (Optional - for connecting to other VPCs)
# Uncomment if needed
# ========================================================
# resource "google_compute_network_peering" "peering" {
#   name         = "poc-peering-${local.environment}"
#   network      = google_compute_network.vpc_network.self_link
#   peer_project = var.peer_project_id
#   peer_network = var.peer_network_self_link
# }
