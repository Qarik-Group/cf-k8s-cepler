# Test of deploying cf to k8s via cepler

## Setup

- create gcp account
- create `terraform` service account
- attach the following roles: `Compute Network Admin`, `Kubernetes Engine Admin`, `Service Account Admin`, `Project IAM Admin`

download a key and run the terraform command:
```
cd terraform && GOOGLE_CLOUD_KEYFILE_JSON=<path-to-keyfile.json> terraform apply
```
