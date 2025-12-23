# AppStack- Terraform (EC2/ASG + ALB + RDS + S3 + WAF + CloudWatch)

## What you get
- VPC with 2 public + 2 private subnets (2 AZs)
- NAT gateway for private outbound
- ALB in public subnets
- ASG in private subnets with **Instance Refresh** for zero downtime
- RDS PostgreSQL Multi-AZ + automated backups (7 days)
- S3 bucket for Django static/media (private, versioned, encrypted)
- AWS WAF attached to ALB (Managed Common Rules)
- CloudWatch alarms + optional SNS email
- Secure Terraform remote state: S3 backend + DynamoDB locking (separate bootstrap stack)

## Start here
Open `docs/STEP_BY_STEP.md`
