locals {
  pods_range_name     = "${local.cluster_name}-pods"
  svc_range_name      = "${local.cluster_name}-svc"
  cluster_network_tag = local.cluster_name
  network_prefix = "10.1"
}

resource google_compute_network "vpc" {
  name                    = "${local.cluster_name}-vpc"
  project                 = local.project
  auto_create_subnetworks = "false"
  routing_mode            = "REGIONAL"
}

resource google_compute_subnetwork "cluster" {

  name = "${local.cluster_name}-cluster"

  project = local.project
  region  = local.region
  network = google_compute_network.vpc.self_link

  private_ip_google_access = true
  ip_cidr_range            = "${local.network_prefix}.0.0/17"
  secondary_ip_range {
    range_name    = local.pods_range_name
    ip_cidr_range = "192.168.0.0/18"
  }
  secondary_ip_range {
    range_name    = local.svc_range_name
    ip_cidr_range = "192.168.64.0/18"
  }
}
