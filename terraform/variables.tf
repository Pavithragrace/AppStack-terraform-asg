variable "aws_region" { type = string, default = "ap-south-1" }
variable "project_name" { type = string, default = "AppStack" }

variable "vpc_cidr" { type = string, default = "10.0.0.0/16" }
variable "public_subnet_cidrs" { type = list(string), default = ["10.0.1.0/24","10.0.2.0/24"] }
variable "private_subnet_cidrs" { type = list(string), default = ["10.0.11.0/24","10.0.12.0/24"] }

variable "db_name" { type = string, default = "appdb" }
variable "db_username" { type = string, default = "appuser" }
variable "db_password" { type = string, sensitive = true }

# Bucket to store Django static/media (NOT terraform state)
variable "static_bucket_prefix" {
  type        = string
  description = "Unique prefix for Django static bucket (example: pavi-appstack-static-2025-unique)"
}

variable "instance_type" { type = string, default = "t3.micro" }

# Optional SSH (recommended: leave blank and use SSM)
variable "key_name" { type = string, default = "" }
variable "allowed_ssh_cidr" { type = string, default = "0.0.0.0/0" }

# Repo for auto-deploy at boot (recommended public repo)
variable "app_repo_url" { type = string, default = "" }
variable "app_repo_ref" { type = string, default = "main" }

# Optional alarm email
variable "alarm_email" { type = string, default = "" }
