locals {
  cluster_name = "cf-on-k8s"
  project      = "cf-on-k8s-cepler"
  region       = "europe-west3"
}

provider "google" {
  version = "~> 3.42.0"
  project = local.project
  region  = local.region
}

data google_client_config "default" {
}

provider "kubernetes" {
  load_config_file       = false
  host                   = module.gke.endpoint
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

module "gke" {
  source                 = "terraform-google-modules/kubernetes-engine/google"
  version                = "11.1.0"
  project_id             = local.project
  name                   = local.cluster_name
  regional               = true
  region                 = local.region
  network                = google_compute_network.vpc.name
  subnetwork             = google_compute_subnetwork.cluster.name
  ip_range_pods          = local.pods_range_name
  ip_range_services      = local.svc_range_name
  create_service_account = false
  service_account        = google_service_account.cluster_service_account.email
  zones = ["${local.region}-a"]

  node_pools = [
    {
      name            = "pool-01"
      machine_type    = "e2-standard-4"
      min_count       = 1
      max_count       = 3
      service_account = google_service_account.cluster_service_account.email
      auto_upgrade    = true
    },
  ]
}
