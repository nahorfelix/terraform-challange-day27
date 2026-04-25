variable "launch_template_ami" {
  description = "AMI ID for EC2 instances in this region"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "subnet_ids" {
  description = "List of private subnet IDs where ASG instances will launch"
  type        = list(string)
}

variable "target_group_arns" {
  description = "List of ALB target group ARNs to attach to the ASG"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group ID — instances allow inbound from ALB only"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the instance security group"
  type        = string
}

variable "min_size" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "Desired number of instances at launch"
  type        = number
  default     = 2
}

variable "cpu_scale_out_threshold" {
  description = "Average CPU % at which to add one instance"
  type        = number
  default     = 70
}

variable "cpu_scale_in_threshold" {
  description = "Average CPU % at which to remove one instance"
  type        = number
  default     = 30
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "region" {
  description = "AWS region this ASG is deployed in"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
