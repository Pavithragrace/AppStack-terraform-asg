variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "AppStack"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  type    = string
  default = ""
}

variable "allowed_ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "app_repo_url" {
  type    = string
  default = ""
}
variable "static_bucket_prefix" {
  type        = string
  description = "Prefix for S3 bucket that stores Django static files (must be globally unique)"
}

variable "app_repo_ref" {
  type    = string
  default = "main"
}

variable "alarm_email" {
  type    = string
  default = ""
}
variable "deploy_id" {
  type    = string
  default = ""
}
