output concourse_token {
  value = data.kubernetes_secret.concourse_token.data.token
}
output k8s_endpoint {
  value                   = "https://${module.gke.endpoint}"
}
output ca_cert_base_64 {
  value = module.gke.ca_certificate
}
