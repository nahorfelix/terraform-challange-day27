output "primary_health_check_id" {
  value       = aws_route53_health_check.primary.id
  description = "ID of the Route53 health check for the primary region"
}

output "secondary_health_check_id" {
  value       = aws_route53_health_check.secondary.id
  description = "ID of the Route53 health check for the secondary region"
}

output "application_url" {
  value       = "http://${var.domain_name}"
  description = "URL of the application via Route53 failover DNS"
}
