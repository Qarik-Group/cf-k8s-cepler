resource kubernetes_service_account "concourse" {
  metadata {
    name = "concourse"
  }
}

resource kubernetes_cluster_role "concourse" {
  metadata {
    name = "concourse"
  }

  rule {
    api_groups = [
      "",
      "apiextensions.k8s.io",
      "networking.k8s.io",
      "apps",
      "jobs",
      "rbac.authorization.k8s.io",
      "policy",
      "batch",
      "scheduling.k8s.io",
      "kpack.io",
      "networking.istio.io",
      "apps.cloudfoundry.org",
      "security.istio.io",
      "admissionregistration.k8s.io",
    ]
    resources = ["*"]
    verbs     = ["*"]
  }
}

resource kubernetes_cluster_role_binding "concourse" {
  metadata {
    name = "concourse"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_service_account.concourse.metadata[0].name
  }
  subject {
    kind = "ServiceAccount"
    name = kubernetes_cluster_role.concourse.metadata[0].name
  }
}

data kubernetes_secret "concourse_token" {
  metadata {
    name = kubernetes_service_account.concourse.default_secret_name
  }
}
