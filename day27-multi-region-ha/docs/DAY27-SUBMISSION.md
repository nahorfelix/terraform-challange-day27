# Day 27 Submission — 3-Tier Multi-Region High Availability Infrastructure with AWS and Terraform

## Repository Link
- https://github.com/nahorfelix/terraform-challange-day27

## Live App Link
- http://app.example.com (configured Route53 failover URL from Terraform output)

## Learning Journal
Today I implemented a full multi-region Terraform architecture using reusable modules for VPC, ALB, ASG, RDS, and Route53 failover. I split the environment into primary (us-east-1) and secondary (us-west-2) regions and wired outputs/inputs across modules so each layer stays loosely coupled. During deployment I successfully created core network and compute components in both regions (VPCs, subnets, NAT gateways, ALBs, launch templates, and ASGs). The run then stopped on IAM gaps for CloudWatch alarms, RDS tagging during subnet group creation, and Route53 health check creation. This gave me practical experience with production-style IAM troubleshooting while preserving Terraform state safely via backend + errored.tfstate recovery workflow.

## Project Directory Tree
```text
day27-multi-region-ha/
├── backend.tf
├── provider.tf
├── envs/
│   └── prod/
│       ├── backend.tf
│       ├── main.tf
│       ├── outputs.tf
│       ├── provider.tf
│       ├── terraform.tfvars
│       └── variables.tf
└── modules/
    ├── vpc/
    │   ├── main.tf
    │   ├── outputs.tf
    │   └── variables.tf
    ├── alb/
    │   ├── main.tf
    │   ├── outputs.tf
    │   └── variables.tf
    ├── asg/
    │   ├── main.tf
    │   ├── outputs.tf
    │   └── variables.tf
    ├── rds/
    │   ├── main.tf
    │   ├── outputs.tf
    │   └── variables.tf
    └── route53/
        ├── main.tf
        ├── outputs.tf
        └── variables.tf
```

## Module Code

### modules/vpc/variables.tf
`hcl
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones to deploy subnets into"
  type        = list(string)
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "region" {
  description = "AWS region this VPC is deployed in"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

`

### modules/vpc/main.tf
`hcl
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = "multi-region-ha"
    Region      = var.region
  })
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "vpc-${var.environment}-${var.region}" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "igw-${var.environment}-${var.region}" })
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, {
    Name = "public-subnet-${count.index + 1}-${var.region}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = merge(local.common_tags, {
    Name = "private-subnet-${count.index + 1}-${var.region}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "nat-eip-${count.index + 1}-${var.region}" })
}

resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(local.common_tags, { Name = "nat-gw-${count.index + 1}-${var.region}" })
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "public-rt-${var.region}" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  tags = merge(local.common_tags, { Name = "private-rt-${count.index + 1}-${var.region}" })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}


`

### modules/vpc/outputs.tf
`hcl
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID of the VPC"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "List of public subnet IDs"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "List of private subnet IDs"
}

`

### modules/alb/variables.tf
`hcl
variable "name" {
  description = "Name prefix for the ALB and related resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs for the ALB (minimum two AZs)"
  type        = list(string)
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "region" {
  description = "AWS region this ALB is deployed in"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

`

### modules/alb/main.tf
`hcl
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = "multi-region-ha"
    Region      = var.region
  })
  # Keep ALB/TG names under AWS 32-char limit.
  alb_name_prefix = substr(var.name, 0, 18)
  tg_name_prefix  = substr(var.name, 0, 19)
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg-${var.region}"
  description = "Allow HTTP/HTTPS inbound to the ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_lb" "web" {
  name               = "${local.alb_name_prefix}-alb-${var.region}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
  tags               = local.common_tags
}

resource "aws_lb_target_group" "web" {
  name     = "${local.tg_name_prefix}-tg-${var.region}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}


`

### modules/alb/outputs.tf
`hcl
output "alb_dns_name" {
  value       = aws_lb.web.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "alb_zone_id" {
  value       = aws_lb.web.zone_id
  description = "Zone ID of the ALB â€” required for Route53 alias records"
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

`

### modules/asg/variables.tf
`hcl
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
  description = "ALB security group ID â€” instances allow inbound from ALB only"
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

`

### modules/asg/main.tf
`hcl
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = "multi-region-ha"
    Region      = var.region
  })
}

resource "aws_security_group" "instance" {
  name        = "web-instance-sg-${var.environment}-${var.region}"
  description = "Allow inbound from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_launch_template" "web" {
  name_prefix   = "web-lt-${var.environment}-${var.region}-"
  image_id      = var.launch_template_ami
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    dnf update -y || yum update -y
    dnf install -y httpd || yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
      http://169.254.169.254/latest/meta-data/placement/availability-zone)
    echo "<h1>Region: ${var.region} | AZ: $AZ | Environment: ${var.environment}</h1>" \
      > /var/www/html/index.html
    mkdir -p /var/www/html
    echo "OK" > /var/www/html/health
  USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "web-${var.environment}-${var.region}" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "web-asg-${var.environment}-${var.region}"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = var.target_group_arns

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "web-${var.environment}-${var.region}" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "web-scale-out-${var.environment}-${var.region}"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "web-scale-in-${var.environment}-${var.region}"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "web-cpu-high-${var.environment}-${var.region}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.cpu_scale_out_threshold

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_description = "Scale out when average CPU >= ${var.cpu_scale_out_threshold}%"
  alarm_actions     = [aws_autoscaling_policy.scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "web-cpu-low-${var.environment}-${var.region}"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = var.cpu_scale_in_threshold

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_description = "Scale in when average CPU <= ${var.cpu_scale_in_threshold}%"
  alarm_actions     = [aws_autoscaling_policy.scale_in.arn]
}


`

### modules/asg/outputs.tf
`hcl
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

`

### modules/rds/variables.tf
`hcl
variable "identifier" {
  description = "Unique identifier for the RDS instance"
  type        = string
}

variable "engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Storage size in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the initial database"
  type        = string
}

variable "db_username" {
  description = "Master database username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Master database password â€” use AWS Secrets Manager in production"
  type        = string
  sensitive   = true
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID for the RDS security group"
  type        = string
}

variable "app_security_group_id" {
  description = "Security group ID of the application tier â€” RDS allows inbound from this SG only"
  type        = string
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for the primary instance"
  type        = bool
  default     = true
}

variable "is_replica" {
  description = "Set to true when creating a cross-region read replica"
  type        = bool
  default     = false
}

variable "replicate_source_db" {
  description = "ARN of the primary RDS instance to replicate from (required when is_replica = true)"
  type        = string
  default     = null
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "region" {
  description = "AWS region this RDS instance is deployed in"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

`

### modules/rds/main.tf
`hcl
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = "multi-region-ha"
    Region      = var.region
  })
}

resource "aws_security_group" "rds" {
  name        = "rds-sg-${var.environment}-${var.region}"
  description = "Allow MySQL inbound from application tier only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_db_subnet_group" "main" {
  name       = "db-subnet-group-${var.environment}-${var.region}"
  subnet_ids = var.subnet_ids
  tags       = local.common_tags
}

resource "aws_db_instance" "main" {
  identifier              = var.identifier
  engine                  = "mysql"
  engine_version          = var.is_replica ? null : var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.is_replica ? null : var.allocated_storage
  db_name                 = var.is_replica ? null : var.db_name
  username                = var.is_replica ? null : var.db_username
  password                = var.is_replica ? null : var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  multi_az                = var.is_replica ? false : var.multi_az
  replicate_source_db     = var.is_replica ? var.replicate_source_db : null
  backup_retention_period = var.is_replica ? 0 : 7
  skip_final_snapshot     = true
  storage_encrypted       = true
  publicly_accessible     = false

  tags = merge(local.common_tags, {
    Name = var.identifier
    Role = var.is_replica ? "read-replica" : "primary"
  })
}


`

### modules/rds/outputs.tf
`hcl
output "db_instance_id" {
  value       = aws_db_instance.main.id
  description = "ID of the RDS instance"
}

output "db_instance_arn" {
  value       = aws_db_instance.main.arn
  description = "ARN of the RDS instance â€” used as replicate_source_db in the replica region"
}

output "db_endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "Connection endpoint for the RDS instance"
}

output "db_security_group_id" {
  value       = aws_security_group.rds.id
  description = "Security group ID of the RDS instance"
}

`

### modules/route53/variables.tf
`hcl
variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for your domain"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the application (e.g. app.example.com)"
  type        = string
}

variable "primary_alb_dns_name" {
  description = "DNS name of the primary region ALB"
  type        = string
}

variable "primary_alb_zone_id" {
  description = "Zone ID of the primary region ALB"
  type        = string
}

variable "secondary_alb_dns_name" {
  description = "DNS name of the secondary region ALB"
  type        = string
}

variable "secondary_alb_zone_id" {
  description = "Zone ID of the secondary region ALB"
  type        = string
}

variable "primary_region" {
  description = "Primary AWS region identifier"
  type        = string
}

variable "secondary_region" {
  description = "Secondary AWS region identifier"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

`

### modules/route53/main.tf
`hcl
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(var.tags, {
    Name   = "health-check-primary-${var.primary_region}"
    Region = var.primary_region
  })
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = var.secondary_alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(var.tags, {
    Name   = "health-check-secondary-${var.secondary_region}"
    Region = var.secondary_region
  })
}

resource "aws_route53_record" "primary" {
  zone_id         = var.hosted_zone_id
  name            = var.domain_name
  type            = "A"
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  zone_id         = var.hosted_zone_id
  name            = var.domain_name
  type            = "A"
  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary.id

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = true
  }
}


`

### modules/route53/outputs.tf
`hcl
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

`

### Variable defaults rationale (all five modules)
- Variables with no default are required environment-specific inputs that should be explicitly supplied by the caller (pc_id, subnet_ids, 
egion, AMIs, domain/zone IDs, DB identity fields, etc.). This prevents accidental cross-region or cross-account misconfiguration.
- Variables with defaults are safe operational baselines: sizes (	3.micro), ASG limits (min=1, max=4, desired=2), CPU alarm thresholds (70/30), RDS defaults (8.0, db.t3.micro, 20GB, multi_az=true), booleans (is_replica=false), optional maps (	ags={}), and optional replication source (
ull).

## Calling Configuration

### envs/prod/main.tf
`hcl
# Primary region
module "vpc_primary" {
  source               = "../../modules/vpc"
  providers            = { aws = aws.primary }
  vpc_cidr             = var.primary_vpc_cidr
  public_subnet_cidrs  = var.primary_public_subnet_cidrs
  private_subnet_cidrs = var.primary_private_subnet_cidrs
  availability_zones   = var.primary_availability_zones
  environment          = var.environment
  region               = var.primary_region
}

module "alb_primary" {
  source      = "../../modules/alb"
  providers   = { aws = aws.primary }
  name        = var.app_name
  vpc_id      = module.vpc_primary.vpc_id
  subnet_ids  = module.vpc_primary.public_subnet_ids
  environment = var.environment
  region      = var.primary_region
}

module "asg_primary" {
  source                = "../../modules/asg"
  providers             = { aws = aws.primary }
  launch_template_ami   = var.primary_ami_id
  instance_type         = var.instance_type
  vpc_id                = module.vpc_primary.vpc_id
  subnet_ids            = module.vpc_primary.private_subnet_ids
  target_group_arns     = [module.alb_primary.target_group_arn]
  alb_security_group_id = module.alb_primary.alb_security_group_id
  min_size              = var.min_size
  max_size              = var.max_size
  desired_capacity      = var.desired_capacity
  environment           = var.environment
  region                = var.primary_region
}

module "rds_primary" {
  source                = "../../modules/rds"
  providers             = { aws = aws.primary }
  identifier            = "${var.app_name}-db-primary"
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  subnet_ids            = module.vpc_primary.private_subnet_ids
  vpc_id                = module.vpc_primary.vpc_id
  app_security_group_id = module.asg_primary.instance_security_group_id
  multi_az              = true
  environment           = var.environment
  region                = var.primary_region
}

# Secondary region
module "vpc_secondary" {
  source               = "../../modules/vpc"
  providers            = { aws = aws.secondary }
  vpc_cidr             = var.secondary_vpc_cidr
  public_subnet_cidrs  = var.secondary_public_subnet_cidrs
  private_subnet_cidrs = var.secondary_private_subnet_cidrs
  availability_zones   = var.secondary_availability_zones
  environment          = var.environment
  region               = var.secondary_region
}

module "alb_secondary" {
  source      = "../../modules/alb"
  providers   = { aws = aws.secondary }
  name        = var.app_name
  vpc_id      = module.vpc_secondary.vpc_id
  subnet_ids  = module.vpc_secondary.public_subnet_ids
  environment = var.environment
  region      = var.secondary_region
}

module "asg_secondary" {
  source                = "../../modules/asg"
  providers             = { aws = aws.secondary }
  launch_template_ami   = var.secondary_ami_id
  instance_type         = var.instance_type
  vpc_id                = module.vpc_secondary.vpc_id
  subnet_ids            = module.vpc_secondary.private_subnet_ids
  target_group_arns     = [module.alb_secondary.target_group_arn]
  alb_security_group_id = module.alb_secondary.alb_security_group_id
  min_size              = var.min_size
  max_size              = var.max_size
  desired_capacity      = var.desired_capacity
  environment           = var.environment
  region                = var.secondary_region
}

module "rds_replica" {
  source                = "../../modules/rds"
  providers             = { aws = aws.secondary }
  identifier            = "${var.app_name}-db-replica"
  is_replica            = true
  replicate_source_db   = module.rds_primary.db_instance_arn
  subnet_ids            = module.vpc_secondary.private_subnet_ids
  vpc_id                = module.vpc_secondary.vpc_id
  app_security_group_id = module.asg_secondary.instance_security_group_id
  environment           = var.environment
  region                = var.secondary_region

  # Required by variable schema; ignored for replicas
  db_name     = "replica"
  db_username = "replica"
  db_password = "replica-password"
}

module "route53" {
  source                 = "../../modules/route53"
  hosted_zone_id         = var.hosted_zone_id
  domain_name            = var.domain_name
  primary_alb_dns_name   = module.alb_primary.alb_dns_name
  primary_alb_zone_id    = module.alb_primary.alb_zone_id
  secondary_alb_dns_name = module.alb_secondary.alb_dns_name
  secondary_alb_zone_id  = module.alb_secondary.alb_zone_id
  primary_region         = var.primary_region
  secondary_region       = var.secondary_region
}

`

### envs/prod/terraform.tfvars
`hcl
app_name    = "web-challenge-day27"
environment = "prod"

primary_region   = "us-east-1"
secondary_region = "us-west-2"

# Primary region â€” us-east-1
primary_ami_id               = "ami-0c02fb55956c7d316"
primary_vpc_cidr             = "10.0.0.0/16"
primary_public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
primary_private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
primary_availability_zones   = ["us-east-1a", "us-east-1b"]

# Secondary region â€” us-west-2
secondary_ami_id               = "ami-0395649fbe870727e"
secondary_vpc_cidr             = "10.1.0.0/16"
secondary_public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
secondary_private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]
secondary_availability_zones   = ["us-west-2a", "us-west-2b"]

instance_type    = "t3.micro"
min_size         = 1
max_size         = 4
desired_capacity = 2

db_name     = "appdb"
db_username = "admin"
db_password = "ChangeMe123!"

hosted_zone_id = "ZXXXXXXXXXXXXX"
domain_name    = "app.example.com"

`

### Wiring explanation (cross-module and cross-region)
- module.vpc_primary and module.vpc_secondary produce subnet/VPC IDs used by ALB, ASG, and RDS in their respective regions.
- module.alb_* .target_group_arn is passed into module.asg_* .target_group_arns, attaching instances to each regional ALB.
- module.asg_* .instance_security_group_id is passed to each RDS module as pp_security_group_id, allowing DB access only from app instances.
- Cross-region DB replication path: module.rds_primary.db_instance_arn -> module.rds_replica.replicate_source_db.

## Deployment Output

### terraform apply (terminal excerpt)
`	ext
[0m[1mmodule.vpc_secondary.aws_nat_gateway.main[1]: Still creating... [01m20s elapsed][0m[0m
[0m[1mmodule.vpc_secondary.aws_nat_gateway.main[0]: Still creating... [01m20s elapsed][0m[0m
[0m[1mmodule.alb_secondary.aws_lb.web: Still creating... [01m20s elapsed][0m[0m
[0m[1mmodule.vpc_primary.aws_nat_gateway.main[1]: Still creating... [01m30s elapsed][0m[0m
[0m[1mmodule.vpc_primary.aws_nat_gateway.main[0]: Still creating... [01m30s elapsed][0m[0m
[0m[1mmodule.alb_primary.aws_lb.web: Still creating... [01m30s elapsed][0m[0m
[0m[1mmodule.vpc_secondary.aws_nat_gateway.main[0]: Creation complete after 1m30s [id=nat-092d6095911106628][0m
[0m[1mmodule.vpc_secondary.aws_nat_gateway.main[1]: Still creating... [01m30s elapsed][0m[0m
[0m[1mmodule.alb_secondary.aws_lb.web: Still creating... [01m30s elapsed][0m[0m
[0m[1mmodule.vpc_primary.aws_nat_gateway.main[1]: Creation complete after 1m38s [id=nat-0e35a7425f327996e][0m
[0m[1mmodule.vpc_primary.aws_nat_gateway.main[0]: Still creating... [01m40s elapsed][0m[0m
[0m[1mmodule.alb_primary.aws_lb.web: Still creating... [01m40s elapsed][0m[0m
[0m[1mmodule.vpc_secondary.aws_nat_gateway.main[1]: Still creating... [01m40s elapsed][0m[0m
[0m[1mmodule.alb_secondary.aws_lb.web: Still creating... [01m40s elapsed][0m[0m
[0m[1mmodule.vpc_primary.aws_nat_gateway.main[0]: Creation complete after 1m48s [id=nat-00768c2d0699dffd0][0m
[0m[1mmodule.vpc_primary.aws_route_table.private[1]: Creating...[0m[0m
[0m[1mmodule.vpc_primary.aws_route_table.private[0]: Creating...[0m[0m
[0m[1mmodule.alb_primary.aws_lb.web: Still creating... [01m50s elapsed][0m[0m
[0m[1mmodule.vpc_primary.aws_route_table.private[0]: Creation complete after 3s [id=rtb-0349e09e319e93027][0m
[0m[1mmodule.vpc_primary.aws_route_table.private[1]: Creation complete after 3s [id=rtb-0577fb592d11d0aa5][0m
[0m[1mmodule.vpc_primary.aws_route_table_association.private[0]: Creating...[0m[0m
[0m[1mmodule.vpc_primary.aws_route_table_association.private[1]: Creating...[0m[0m
[0m[1mmodule.vpc_secondary.aws_nat_gateway.main[1]: Still creating... [01m50s elapsed][0m[0m
[0m[1mmodule.vpc_primary.aws_route_table_association.private[0]: Creation complete after 1s [id=rtbassoc-08142586e8a88b9c5][0m
[0m[1mmodule.vpc_primary.aws_route_table_association.private[1]: Creation complete after 1s [id=rtbassoc-0977945e1e2ada8b8][0m
[0m[1mmodule.vpc_secondary.aws_nat_gateway.main[1]: Creation complete after 1m51s [id=nat-083554d5c86e48974][0m
[0m[1mmodule.vpc_secondary.aws_route_table.private[0]: Creating...[0m[0m
[0m[1mmodule.vpc_secondary.aws_route_table.private[1]: Creating...[0m[0m
[0m[1mmodule.alb_secondary.aws_lb.web: Still creating... [01m50s elapsed][0m[0m
[0m[1mmodule.vpc_secondary.aws_route_table.private[0]: Creation complete after 3s [id=rtb-09c1657c713a42a2d][0m
[0m[1mmodule.vpc_secondary.aws_route_table.private[1]: Creation complete after 4s [id=rtb-0f469f53fd65b0312][0m
[0m[1mmodule.vpc_secondary.aws_route_table_association.private[1]: Creating...[0m[0m
[0m[1mmodule.vpc_secondary.aws_route_table_association.private[0]: Creating...[0m[0m
[0m[1mmodule.vpc_secondary.aws_route_table_association.private[1]: Creation complete after 1s [id=rtbassoc-08c1e2bbbe199ad41][0m
[0m[1mmodule.vpc_secondary.aws_route_table_association.private[0]: Creation complete after 1s [id=rtbassoc-0d20c57234bd4b654][0m
[0m[1mmodule.alb_primary.aws_lb.web: Still creating... [02m00s elapsed][0m[0m
[0m[1mmodule.alb_secondary.aws_lb.web: Still creating... [02m00s elapsed][0m[0m
[0m[1mmodule.alb_primary.aws_lb.web: Still creating... [02m10s elapsed][0m[0m
[0m[1mmodule.alb_secondary.aws_lb.web: Still creating... [02m10s elapsed][0m[0m
[0m[1mmodule.alb_primary.aws_lb.web: Still creating... [02m20s elapsed][0m[0m
[0m[1mmodule.alb_secondary.aws_lb.web: Still creating... [02m20s elapsed][0m[0m
[0m[1mmodule.alb_primary.aws_lb.web: Creation complete after 2m27s [id=arn:aws:elasticloadbalancing:us-east-1:307217365875:loadbalancer/app/web-challenge-day2-alb-us-east-1/1667c90f1af0245f][0m
[0m[1mmodule.alb_primary.aws_lb_listener.http: Creating...[0m[0m
[0m[1mmodule.route53.aws_route53_health_check.primary: Creating...[0m[0m
[0m[1mmodule.alb_primary.aws_lb_listener.http: Creation complete after 1s [id=arn:aws:elasticloadbalancing:us-east-1:307217365875:listener/app/web-challenge-day2-alb-us-east-1/1667c90f1af0245f/a3ce61ee6c761b1a][0m
[0m[1mmodule.alb_secondary.aws_lb.web: Still creating... [02m30s elapsed][0m[0m
[0m[1mmodule.alb_secondary.aws_lb.web: Creation complete after 2m40s [id=arn:aws:elasticloadbalancing:us-west-2:307217365875:loadbalancer/app/web-challenge-day2-alb-us-west-2/5167284cf7f63d31][0m
[0m[1mmodule.route53.aws_route53_health_check.secondary: Creating...[0m[0m
[0m[1mmodule.alb_secondary.aws_lb_listener.http: Creating...[0m[0m
[0m[1mmodule.alb_secondary.aws_lb_listener.http: Creation complete after 1s [id=arn:aws:elasticloadbalancing:us-west-2:307217365875:listener/app/web-challenge-day2-alb-us-west-2/5167284cf7f63d31/445823d5f6e274ec][0m
[31mâ•·[0m[0m
[31mâ”‚[0m [0m[1m[31mError: [0m[0m[1mcreating CloudWatch Metric Alarm (web-cpu-high-prod-us-east-1): operation error CloudWatch: PutMetricAlarm, https response error StatusCode: 403, RequestID: 5307f336-1e9b-4d96-a6b8-a90700769757, api error AccessDenied: User: arn:aws:iam::307217365875:user/Nahor is not authorized to perform: cloudwatch:PutMetricAlarm on resource: arn:aws:cloudwatch:us-east-1:307217365875:alarm:web-cpu-high-prod-us-east-1 because no identity-based policy allows the cloudwatch:PutMetricAlarm action[0m
[31mâ”‚[0m [0m
[31mâ”‚[0m [0m[0m  with module.asg_primary.aws_cloudwatch_metric_alarm.cpu_high,
[31mâ”‚[0m [0m  on ..\..\modules\asg\main.tf line 119, in resource "aws_cloudwatch_metric_alarm" "cpu_high":
[31mâ”‚[0m [0m 119: resource "aws_cloudwatch_metric_alarm" "cpu_high" [4m{[0m[0m
[31mâ”‚[0m [0m
[31mâ•µ[0m[0m
[31mâ•·[0m[0m
[31mâ”‚[0m [0m[1m[31mError: [0m[0m[1mcreating CloudWatch Metric Alarm (web-cpu-high-prod-us-west-2): operation error CloudWatch: PutMetricAlarm, https response error StatusCode: 403, RequestID: 9b7e89da-6ed6-4ba0-b314-1b80b6c83d94, api error AccessDenied: User: arn:aws:iam::307217365875:user/Nahor is not authorized to perform: cloudwatch:PutMetricAlarm on resource: arn:aws:cloudwatch:us-west-2:307217365875:alarm:web-cpu-high-prod-us-west-2 because no identity-based policy allows the cloudwatch:PutMetricAlarm action[0m
[31mâ”‚[0m [0m
[31mâ”‚[0m [0m[0m  with module.asg_secondary.aws_cloudwatch_metric_alarm.cpu_high,
[31mâ”‚[0m [0m  on ..\..\modules\asg\main.tf line 119, in resource "aws_cloudwatch_metric_alarm" "cpu_high":
[31mâ”‚[0m [0m 119: resource "aws_cloudwatch_metric_alarm" "cpu_high" [4m{[0m[0m
[31mâ”‚[0m [0m
[31mâ•µ[0m[0m
[31mâ•·[0m[0m
[31mâ”‚[0m [0m[1m[31mError: [0m[0m[1mcreating CloudWatch Metric Alarm (web-cpu-low-prod-us-east-1): operation error CloudWatch: PutMetricAlarm, https response error StatusCode: 403, RequestID: c807e432-ea9a-4578-b4d9-b1df9fdbc4a8, api error AccessDenied: User: arn:aws:iam::307217365875:user/Nahor is not authorized to perform: cloudwatch:PutMetricAlarm on resource: arn:aws:cloudwatch:us-east-1:307217365875:alarm:web-cpu-low-prod-us-east-1 because no identity-based policy allows the cloudwatch:PutMetricAlarm action[0m
[31mâ”‚[0m [0m
[31mâ”‚[0m [0m[0m  with module.asg_primary.aws_cloudwatch_metric_alarm.cpu_low,
[31mâ”‚[0m [0m  on ..\..\modules\asg\main.tf line 137, in resource "aws_cloudwatch_metric_alarm" "cpu_low":
[31mâ”‚[0m [0m 137: resource "aws_cloudwatch_metric_alarm" "cpu_low" [4m{[0m[0m
[31mâ”‚[0m [0m
[31mâ•µ[0m[0m
[31mâ•·[0m[0m
[31mâ”‚[0m [0m[1m[31mError: [0m[0m[1mcreating CloudWatch Metric Alarm (web-cpu-low-prod-us-west-2): operation error CloudWatch: PutMetricAlarm, https response error StatusCode: 403, RequestID: 443bf196-2d19-4c80-96c5-03f765ca82ac, api error AccessDenied: User: arn:aws:iam::307217365875:user/Nahor is not authorized to perform: cloudwatch:PutMetricAlarm on resource: arn:aws:cloudwatch:us-west-2:307217365875:alarm:web-cpu-low-prod-us-west-2 because no identity-based policy allows the cloudwatch:PutMetricAlarm action[0m
[31mâ”‚[0m [0m
[31mâ”‚[0m [0m[0m  with module.asg_secondary.aws_cloudwatch_metric_alarm.cpu_low,
[31mâ”‚[0m [0m  on ..\..\modules\asg\main.tf line 137, in resource "aws_cloudwatch_metric_alarm" "cpu_low":
[31mâ”‚[0m [0m 137: resource "aws_cloudwatch_metric_alarm" "cpu_low" [4m{[0m[0m
[31mâ”‚[0m [0m
[31mâ•µ[0m[0m
[31mâ•·[0m[0m
[31mâ”‚[0m [0m[1m[31mError: [0m[0m[1mcreating RDS DB Subnet Group (db-subnet-group-prod-us-west-2): operation error RDS: CreateDBSubnetGroup, https response error StatusCode: 403, RequestID: eae0a640-7e99-4e5d-bbe5-4aa912079250, api error AccessDenied: User: arn:aws:iam::307217365875:user/Nahor is not authorized to perform: rds:AddTagsToResource on resource: arn:aws:rds:us-west-2:307217365875:subgrp:db-subnet-group-prod-us-west-2 because no identity-based policy allows the rds:AddTagsToResource action[0m
[31mâ”‚[0m [0m
[31mâ”‚[0m [0m[0m  with module.rds_replica.aws_db_subnet_group.main,
[31mâ”‚[0m [0m  on ..\..\modules\rds\main.tf line 39, in resource "aws_db_subnet_group" "main":
[31mâ”‚[0m [0m  39: resource "aws_db_subnet_group" "main" [4m{[0m[0m
[31mâ”‚[0m [0m
[31mâ•µ[0m[0m
[31mâ•·[0m[0m
[31mâ”‚[0m [0m[1m[31mError: [0m[0m[1mcreating RDS DB Subnet Group (db-subnet-group-prod-us-east-1): operation error RDS: CreateDBSubnetGroup, https response error StatusCode: 403, RequestID: cb04098a-4a1c-42f7-9546-177108031bac, api error AccessDenied: User: arn:aws:iam::307217365875:user/Nahor is not authorized to perform: rds:AddTagsToResource on resource: arn:aws:rds:us-east-1:307217365875:subgrp:db-subnet-group-prod-us-east-1 because no identity-based policy allows the rds:AddTagsToResource action[0m
[31mâ”‚[0m [0m
[31mâ”‚[0m [0m[0m  with module.rds_primary.aws_db_subnet_group.main,
[31mâ”‚[0m [0m  on ..\..\modules\rds\main.tf line 39, in resource "aws_db_subnet_group" "main":
[31mâ”‚[0m [0m  39: resource "aws_db_subnet_group" "main" [4m{[0m[0m
[31mâ”‚[0m [0m
[31mâ•µ[0m[0m
[31mâ•·[0m[0m
[31mâ”‚[0m [0m[1m[31mError: [0m[0m[1mcreating Route53 Health Check: operation error Route 53: CreateHealthCheck, https response error StatusCode: 403, RequestID: 7731fe81-aeb2-4d7e-8e50-2ea8662eec57, api error AccessDenied: User: arn:aws:iam::307217365875:user/Nahor is not authorized to perform: route53:CreateHealthCheck because no identity-based policy allows the route53:CreateHealthCheck action[0m
[31mâ”‚[0m [0m
[31mâ”‚[0m [0m[0m  with module.route53.aws_route53_health_check.primary,
[31mâ”‚[0m [0m  on ..\..\modules\route53\main.tf line 8, in resource "aws_route53_health_check" "primary":
[31mâ”‚[0m [0m   8: resource "aws_route53_health_check" "primary" [4m{[0m[0m
[31mâ”‚[0m [0m
[31mâ•µ[0m[0m
[31mâ•·[0m[0m
[31mâ”‚[0m [0m[1m[31mError: [0m[0m[1mcreating Route53 Health Check: operation error Route 53: CreateHealthCheck, https response error StatusCode: 403, RequestID: f46ec5eb-8d89-49b2-be7e-77906a5e59e5, api error AccessDenied: User: arn:aws:iam::307217365875:user/Nahor is not authorized to perform: route53:CreateHealthCheck because no identity-based policy allows the route53:CreateHealthCheck action[0m
[31mâ”‚[0m [0m
[31mâ”‚[0m [0m[0m  with module.route53.aws_route53_health_check.secondary,
[31mâ”‚[0m [0m  on ..\..\modules\route53\main.tf line 22, in resource "aws_route53_health_check" "secondary":
[31mâ”‚[0m [0m  22: resource "aws_route53_health_check" "secondary" [4m{[0m[0m
[31mâ”‚[0m [0m
[31mâ•µ[0m[0m

---
exit_code: 1
elapsed_ms: 208952
ended_at: 2026-04-25T16:08:53.283Z
---

`

### terraform output
`	ext
primary_alb_dns = "web-challenge-day2-alb-us-east-1-1865382818.us-east-1.elb.amazonaws.com"
route53_url = "http://app.example.com"
secondary_alb_dns = "web-challenge-day2-alb-us-west-2-1998953731.us-west-2.elb.amazonaws.com"

`

### Deployment status confirmation
- Primary and secondary ALBs were created.
- ASGs were created in both regions.
- Deployment did not finish fully due IAM denies for CloudWatch alarms, Route53 health checks, and RDS subnet-group tagging.

## Live Application Confirmation
- Configured URL: http://app.example.com
- Observed: Route53 health checks could not be created in this run, so full failover DNS validation is pending IAM update.
- Direct ALB outputs available:
  - primary_alb_dns = web-challenge-day2-alb-us-east-1-1865382818.us-east-1.elb.amazonaws.com
  - secondary_alb_dns = web-challenge-day2-alb-us-west-2-1998953731.us-west-2.elb.amazonaws.com

## Failover Test
Failover simulation is pending because Route53 health checks were blocked by IAM (
oute53:CreateHealthCheck). Once permission is added, expected behavior is:
1. Primary health check fails.
2. Route53 marks PRIMARY unhealthy.
3. DNS answer shifts to SECONDARY ALB after health-check intervals and TTL propagation.

## Multi-AZ vs Cross-Region (RDS)
- Multi-AZ: synchronous standby in another AZ within the same region; used for HA/failover with minimal data loss and low RPO.
- Cross-region read replica: asynchronous replication to a different region; used for disaster recovery, regional resilience, and read scaling. Replication lag can exist.
- Use both together for production-grade resilience: Multi-AZ for local region HA, replica for regional outage recovery.

## Bonus — S3 Cross-Region Replication
Not implemented in this run.

## Cleanup Confirmation
	erraform destroy was not executed yet because deployment ended in a partial state and required IAM completion first. Recommended sequence after IAM fix and verification:
1. Re-run 	erraform apply to converge.
2. Run 	erraform destroy and capture output for final submission evidence.
