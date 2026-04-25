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

