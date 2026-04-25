output "alb_dns_name" {
  value       = aws_lb.web.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "alb_zone_id" {
  value       = aws_lb.web.zone_id
  description = "Zone ID of the ALB — required for Route53 alias records"
}

output "target_group_arn" {
  value       = aws_lb_target_group.web.arn
  description = "ARN of the ALB target group, consumed by the ASG module"
}

output "alb_arn_suffix" {
  value       = aws_lb.web.arn_suffix
  description = "ARN suffix for CloudWatch metrics"
}

output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "Security group ID of the ALB"
}
