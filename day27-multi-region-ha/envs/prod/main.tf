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
