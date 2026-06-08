output "railway_project_id" {
  description = "Railway project ID"
  value       = railway_project.staffos.id
}

output "web_service_id" {
  description = "Railway web service ID"
  value       = railway_service.web.id
}

output "custom_domain" {
  description = "Custom domain configured"
  value       = var.domain
}

output "railway_dns_target" {
  description = "Railway CNAME target for DNS"
  value       = railway_custom_domain.staffos.dns_record_value
}
