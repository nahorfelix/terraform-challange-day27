output "asg_name" {
  value       = aws_autoscaling_group.web.name
  description = "Name of the Auto Scaling Group"
}

output "asg_arn" {
  value       = aws_autoscaling_group.web.arn
  description = "ARN of the Auto Scaling Group"
}

output "instance_security_group_id" {
  value       = aws_security_group.instance.id
  description = "Security group ID of ASG instances"
}
