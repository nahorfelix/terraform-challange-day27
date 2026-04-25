# Day 27: 3-Tier Multi-Region High Availability Infrastructure

## Repository Link
- https://github.com/nahorfelix/terraform-challange-day27

## Live App Link
- Route53 is currently disabled in this run: `Route53 disabled (set enable_route53=true with a valid hosted_zone_id)`
- Primary ALB URL: `http://web-challenge-day2-alb-us-east-1-73787238.us-east-1.elb.amazonaws.com`

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

## Module Code (Key Sections)

### modules/vpc/main.tf — VPC with public/private subnets and NAT gateways
```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
}
```

### modules/alb/main.tf — ALB with target group and health checks
```hcl
resource "aws_lb" "web" {
  name               = "${local.alb_name_prefix}-alb-${var.region}"
  load_balancer_type = "application"
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "web" {
  name     = "${local.tg_name_prefix}-tg-${var.region}"
  port     = 80
  protocol = "HTTP"
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}
```

### modules/asg/main.tf — Auto Scaling with CPU-based scaling
```hcl
resource "aws_autoscaling_group" "web" {
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  target_group_arns         = var.target_group_arns
  health_check_type         = "ELB"
  wait_for_capacity_timeout = "0"
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  threshold     = var.cpu_scale_out_threshold
  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
}
```

### modules/rds/main.tf — Multi-AZ primary with cross-region replica
```hcl
resource "aws_db_instance" "main" {
  identifier          = var.identifier
  engine              = "mysql"
  multi_az            = var.is_replica ? false : var.multi_az
  storage_encrypted   = true
  replicate_source_db = var.is_replica ? var.replicate_source_db : null
  kms_key_id          = var.is_replica ? var.replica_kms_key_id : null
}
```

### modules/route53/main.tf — Failover DNS
```hcl
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns_name
  resource_path     = "/health"
  failure_threshold = 3
}

resource "aws_route53_record" "primary" {
  failover_routing_policy { type = "PRIMARY" }
  health_check_id = aws_route53_health_check.primary.id
}
```

## Calling Configuration

### envs/prod/main.tf — Wiring modules together
```hcl
module "vpc_primary" {
  source = "../../modules/vpc"
  region = var.primary_region
}

module "alb_primary" {
  source     = "../../modules/alb"
  vpc_id     = module.vpc_primary.vpc_id
  subnet_ids = module.vpc_primary.public_subnet_ids
}

module "asg_primary" {
  source             = "../../modules/asg"
  target_group_arns  = [module.alb_primary.target_group_arn]
  launch_template_ami = var.primary_ami_id
}

module "rds_primary" {
  source   = "../../modules/rds"
  multi_az = true
}

module "rds_replica" {
  source              = "../../modules/rds"
  is_replica          = true
  replicate_source_db = module.rds_primary.db_instance_arn
}
```

Cross-region linkage used in my run:
- `module.rds_primary.db_instance_arn` -> `module.rds_replica.replicate_source_db`

## Deployment Output
```text
$ terraform apply -auto-approve
Apply complete! Resources: 4 added, 2 changed, 0 destroyed.

Outputs:
primary_alb_dns = "web-challenge-day2-alb-us-east-1-73787238.us-east-1.elb.amazonaws.com"
secondary_alb_dns = "web-challenge-day2-alb-us-west-2-1538405338.us-west-2.elb.amazonaws.com"
primary_db_endpoint = "web-challenge-day27-db-primary.cc1isia4w74s.us-east-1.rds.amazonaws.com:3306"
replica_db_endpoint = "web-challenge-day27-db-replica.cx0imci262my.us-west-2.rds.amazonaws.com:3306"
route53_url = "Route53 disabled (set enable_route53=true with a valid hosted_zone_id)"
```

## Live Application Confirmation
- Primary ALB DNS opened: `http://web-challenge-day2-alb-us-east-1-73787238.us-east-1.elb.amazonaws.com`
- Secondary ALB DNS available: `http://web-challenge-day2-alb-us-west-2-1538405338.us-west-2.elb.amazonaws.com`
- ASG and RDS resources are provisioned across both regions.
- Route53 failover records are intentionally disabled until a valid hosted zone ID is provided.

## Failover Test
- Route53 failover test is pending because `enable_route53 = false` and `hosted_zone_id` is still placeholder.
- Once real hosted zone is provided, enable Route53 and rerun apply to validate automatic failover.

## Multi-AZ vs Cross-Region
- Multi-AZ: synchronous standby in same region for high availability and quick failover.
- Cross-region replica: asynchronous replica in another region for disaster recovery and regional resilience.

## Bonus — S3 Cross-Region Replication
- Not implemented in this run.

## Cleanup Confirmation
- Destroy not executed yet in this run.
- Final cleanup command when ready:
```bash
terraform destroy -auto-approve
```
