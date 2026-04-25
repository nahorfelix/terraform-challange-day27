output "primary_alb_dns" {
  value       = module.alb_primary.alb_dns_name
  description = "Primary region ALB DNS"
}

output "secondary_alb_dns" {
  value       = module.alb_secondary.alb_dns_name
  description = "Secondary region ALB DNS"
}

output "route53_url" {
  value       = module.route53.application_url
  description = "Route53 failover URL"
}

output "primary_db_endpoint" {
  value       = module.rds_primary.db_endpoint
  description = "Primary DB endpoint"
}

output "replica_db_endpoint" {
  value       = module.rds_replica.db_endpoint
  description = "Replica DB endpoint"
}
