variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "state_bucket_name" {
  type        = string
  description = "S3 bucket name for Terraform remote state (must be globally unique)"
}

variable "dynamodb_table_name" {
  type        = string
  default     = "appstack-terraform-locks"
  description = "DynamoDB table for Terraform state locking"
}
