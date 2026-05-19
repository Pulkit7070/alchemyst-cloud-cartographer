output "gateway_public_ip"    { value = google_compute_instance.gateway.network_interface[0].access_config[0].nat_ip }
output "gateway_internal_ip"  { value = google_compute_address.gateway_internal.address }
output "gateway_self_link"    { value = google_compute_instance.gateway.self_link }
output "inference_self_link"  { value = google_compute_instance.inference.self_link }
output "inference_internal_ip" { value = google_compute_instance.inference.network_interface[0].network_ip }
