terraform {
  backend "gcs" {
    # Populated via -backend-config or TF_BACKEND_* env vars during init.
    # Run scripts/bootstrap.sh first to create this bucket.
    # bucket = "alchemyst-tf-state-<project-id>"
    # prefix = "cloud-cartographer"
  }
}
