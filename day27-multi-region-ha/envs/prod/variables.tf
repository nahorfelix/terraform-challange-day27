variable "app_name" { type = string }
variable "environment" { type = string }

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "secondary_region" {
  type    = string
  default = "us-west-2"
}

variable "primary_ami_id" { type = string }
variable "secondary_ami_id" { type = string }

variable "primary_vpc_cidr" { type = string }
variable "primary_public_subnet_cidrs" { type = list(string) }
variable "primary_private_subnet_cidrs" { type = list(string) }
variable "primary_availability_zones" { type = list(string) }

variable "secondary_vpc_cidr" { type = string }
variable "secondary_public_subnet_cidrs" { type = list(string) }
variable "secondary_private_subnet_cidrs" { type = list(string) }
variable "secondary_availability_zones" { type = list(string) }

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "db_name" { type = string }
variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "hosted_zone_id" { type = string }
variable "domain_name" { type = string }
