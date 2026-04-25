output "db_instance_id" {
  value       = aws_db_instance.main.id
  description = "ID of the RDS instance"
}

output "db_instance_arn" {
  value       = aws_db_instance.main.arn
  description = "ARN of the RDS instance — used as replicate_source_db in the replica region"
}

output "db_endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "Connection endpoint for the RDS instance"
}

output "db_security_group_id" {
  value       = aws_security_group.rds.id
  description = "Security group ID of the RDS instance"
}
