# Day 27 — 3-Tier Multi-Region High Availability (AWS + Terraform)

Public repo for Terraform Challenge Day 27.

## Implemented

- `modules/vpc`: VPC, subnets, NAT gateways, route tables (per region)
- `modules/alb`: ALB, target group, listener
- `modules/asg`: launch template, ASG, CPU scale policies/alarms
- `modules/rds`: primary Multi-AZ RDS and cross-region replica support
- `modules/route53`: failover records + health checks
- `envs/prod`: multi-region wiring (`us-east-1` primary, `us-west-2` secondary)

## Run

```powershell
Set-Location day27-multi-region-ha/envs/prod
terraform init
terraform validate
terraform plan
terraform apply
terraform output
```

## Notes

- Replace placeholders in `envs/prod/terraform.tfvars` (Route53 zone/domain, DB credentials, etc.)
- This architecture is expensive (NAT gateways + ALB + ASG + RDS in two regions). Destroy after verification:

```powershell
terraform destroy
```
