variable "project_id" {
  type        = string
  description = "GCP project ID"

  validation {
    condition     = length(var.project_id) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  type        = string
  description = "Primary GCP region"
  default     = "asia-south1"
}

variable "zone" {
  type        = string
  description = "Primary GCP zone"
  default     = "asia-south1-a"
}

variable "app_version" {
  type        = string
  description = "Git SHA or release tag of the application bundle in GCS"
  default     = "latest"
}

variable "gateway_machine_type" {
  type    = string
  default = "e2-small"
}

variable "inference_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "owner_email" {
  type        = string
  description = "Email of the engineer deploying this stack (granted IAP + OS Login access)"
}

variable "alert_notification_email" {
  type        = string
  description = "Email for Cloud Monitoring alerts"
  default     = ""
}

variable "domain" {
  type        = string
  description = "Domain for the HTTPS LB managed cert (optional). Leave empty to use HTTP only."
  default     = ""
}

variable "labels" {
  type = map(string)
  default = {
    env     = "assignment"
    managed = "terraform"
    owner   = "pulkit"
  }
}
