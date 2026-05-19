output "gateway_sa_email"   { value = google_service_account.gateway.email }
output "inference_sa_email" { value = google_service_account.inference.email }
