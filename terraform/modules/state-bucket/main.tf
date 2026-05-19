variable "project_id" { type = string }
variable "region"     { type = string; default = "asia-south1" }

resource "google_storage_bucket" "tf_state" {
  project                     = var.project_id
  name                        = "${var.project_id}-tf-state"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning { enabled = true }

  retention_policy {
    is_locked        = false
    retention_period = 2592000 # 30 days
  }

  lifecycle_rule {
    action { type = "Delete" }
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
  }
}

output "bucket_name" { value = google_storage_bucket.tf_state.name }
