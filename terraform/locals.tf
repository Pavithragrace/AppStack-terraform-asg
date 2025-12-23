data "aws_availability_zones" "available" {}

locals {
  azs                = slice(data.aws_availability_zones.available.names, 0, 2)
  name_prefix        = lower(var.project_name)
  tags               = { Project = var.project_name }
  static_bucket_name = "${var.static_bucket_prefix}-static"
}
