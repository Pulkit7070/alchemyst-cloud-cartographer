output "dashboard_name" { value = google_monitoring_dashboard.main.id }
output "uptime_check_id" { value = google_monitoring_uptime_check_config.api.uptime_check_id }
