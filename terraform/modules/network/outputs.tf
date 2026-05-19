output "vpc_self_link" {
  value = google_compute_network.vpc.self_link
}

output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "public_subnet_self_link" {
  value = google_compute_subnetwork.public.self_link
}

output "private_subnet_self_link" {
  value = google_compute_subnetwork.private.self_link
}

output "public_subnet_cidr" {
  value = google_compute_subnetwork.public.ip_cidr_range
}

output "private_subnet_cidr" {
  value = google_compute_subnetwork.private.ip_cidr_range
}
