########################
# Data
########################
data "aws_caller_identity" "current" {}

# Ubuntu 22.04 LTS AMI (Canonical)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter { name = "name", values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] }
  filter { name = "virtualization-type", values = ["hvm"] }
}

########################
# 1) Networking (VPC, public/private subnets, IGW, NAT)
########################
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, { Name = "${var.project_name}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.project_name}-igw" })
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = merge(local.tags, { Name = "${var.project_name}-public-${count.index+1}" })
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = merge(local.tags, { Name = "${var.project_name}-private-${count.index+1}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.project_name}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.project_name}-nat-eip" })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
  tags          = merge(local.tags, { Name = "${var.project_name}-nat" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.project_name}-private-rt" })
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

########################
# 2) S3 (Django static/media)
########################
resource "aws_s3_bucket" "static" {
  bucket = local.static_bucket_name
  tags   = merge(local.tags, { Name = "${var.project_name}-static" })
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "static" {
  bucket = aws_s3_bucket.static.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

########################
# 3) Security Groups
########################
resource "aws_security_group" "alb" {
  name   = "${var.project_name}-alb-sg"
  vpc_id = aws_vpc.this.id

  ingress { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }

  tags = merge(local.tags, { Name = "${var.project_name}-alb-sg" })
}

resource "aws_security_group" "app" {
  name   = "${var.project_name}-app-sg"
  vpc_id = aws_vpc.this.id

  # ALB -> app (gunicorn)
  ingress { from_port = 8000, to_port = 8000, protocol = "tcp", security_groups = [aws_security_group.alb.id] }

  # Optional SSH if you set key_name (SSM recommended)
  dynamic "ingress" {
    for_each = var.key_name != "" ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.allowed_ssh_cidr]
    }
  }

  egress { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }

  tags = merge(local.tags, { Name = "${var.project_name}-app-sg" })
}

resource "aws_security_group" "rds" {
  name   = "${var.project_name}-rds-sg"
  vpc_id = aws_vpc.this.id

  # app -> RDS
  ingress { from_port = 5432, to_port = 5432, protocol = "tcp", security_groups = [aws_security_group.app.id] }
  egress  { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }

  tags = merge(local.tags, { Name = "${var.project_name}-rds-sg" })
}

########################
# 4) RDS PostgreSQL (Multi-AZ + backups)
########################
resource "aws_db_subnet_group" "db" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags       = local.tags
}

resource "aws_db_instance" "postgres" {
  identifier              = "${var.project_name}-postgres"
  engine                  = "postgres"
  engine_version          = "15"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_encrypted       = true

  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  port                    = 5432

  multi_az                = true
  backup_retention_period = 7
  publicly_accessible     = false

  skip_final_snapshot     = true
  deletion_protection     = false

  db_subnet_group_name    = aws_db_subnet_group.db.name
  vpc_security_group_ids  = [aws_security_group.rds.id]

  tags = local.tags
}

########################
# 5) SSM Parameter Store (app reads these on boot)
########################
resource "aws_ssm_parameter" "db_host" {
  name  = "/${var.project_name}/db_host"
  type  = "String"
  value = aws_db_instance.postgres.address
  tags  = local.tags
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/${var.project_name}/db_name"
  type  = "String"
  value = var.db_name
  tags  = local.tags
}

resource "aws_ssm_parameter" "db_user" {
  name  = "/${var.project_name}/db_user"
  type  = "String"
  value = var.db_username
  tags  = local.tags
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project_name}/db_password"
  type  = "SecureString"
  value = var.db_password
  tags  = local.tags
}

resource "aws_ssm_parameter" "static_bucket" {
  name  = "/${var.project_name}/static_bucket"
  type  = "String"
  value = aws_s3_bucket.static.bucket
  tags  = local.tags
}

########################
# 6) ALB (Tier-1)
########################
resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  subnets            = [for s in aws_subnet.public : s.id]
  security_groups    = [aws_security_group.alb.id]
  tags               = local.tags
}

resource "aws_lb_target_group" "tg" {
  name        = "${var.project_name}-tg"
  vpc_id      = aws_vpc.this.id
  port        = 8000
  protocol    = "HTTP"
  target_type = "instance"

  health_check {
    path                = "/health"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action { type = "forward", target_group_arn = aws_lb_target_group.tg.arn }
}

########################
# 7) IAM for EC2 (SSM + CloudWatch + S3 + SSM params + KMS decrypt)
########################
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service", identifiers = ["ec2.amazonaws.com"] }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.tags
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.project_name}-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "ec2_inline" {
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParameterHistory"]
    resources = [
      aws_ssm_parameter.db_host.arn,
      aws_ssm_parameter.db_name.arn,
      aws_ssm_parameter.db_user.arn,
      aws_ssm_parameter.db_password.arn,
      aws_ssm_parameter.static_bucket.arn
    ]
  }

  # SecureString decrypt (default SSM KMS key)
  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }

  statement { actions = ["s3:ListBucket"], resources = [aws_s3_bucket.static.arn] }
  statement { actions = ["s3:GetObject","s3:PutObject","s3:DeleteObject"], resources = ["${aws_s3_bucket.static.arn}/*"] }
}

resource "aws_iam_role_policy" "ec2_inline" {
  name   = "${var.project_name}-inline"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ec2_inline.json
}

########################
# 8) Launch Template + ASG (Tier-2) + Instance Refresh (Zero-downtime)
########################
locals {
  user_data = templatefile("${path.module}/user_data_app.sh", {
    aws_region   = var.aws_region
    param_prefix = "/${var.project_name}"
    app_repo_url = var.app_repo_url
    app_repo_ref = var.app_repo_ref
  })
}

resource "aws_launch_template" "lt" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  iam_instance_profile { name = aws_iam_instance_profile.profile.name }
  vpc_security_group_ids = [aws_security_group.app.id]
  user_data = base64encode(local.user_data)

  key_name = var.key_name != "" ? var.key_name : null

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.tags, { Name = "${var.project_name}-app" })
  }
}

resource "aws_autoscaling_group" "asg" {
  name                      = "${var.project_name}-asg"
  vpc_zone_identifier       = [for s in aws_subnet.private : s.id]
  desired_capacity          = 2
  min_size                  = 2
  max_size                  = 4

  health_check_type         = "ELB"
  health_check_grace_period = 240
  target_group_arns         = [aws_lb_target_group.tg.arn]

  launch_template { id = aws_launch_template.lt.id, version = "$Latest" }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
      instance_warmup        = 180
      skip_matching          = true
    }
    triggers = ["launch_template"]
  }

  tag { key = "Name", value = "${var.project_name}-app", propagate_at_launch = true }
  lifecycle { create_before_destroy = true }
}

resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.project_name}-cpu-target"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.asg.name

  target_tracking_configuration {
    predefined_metric_specification { predefined_metric_type = "ASGAverageCPUUtilization" }
    target_value = 60
  }
}

########################
# 9) WAF (Regional) attached to ALB
########################
resource "aws_wafv2_web_acl" "waf" {
  name  = "${var.project_name}-waf"
  scope = "REGIONAL"

  default_action { allow {} }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement { name = "AWSManagedRulesCommonRuleSet", vendor_name = "AWS" }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.tags
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.alb.arn
  web_acl_arn  = aws_wafv2_web_acl.waf.arn
}

########################
# 10) CloudWatch alarms (ALB 5XX + CPU)
########################
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5

  dimensions = {
    LoadBalancer = aws_lb.alb.arn_suffix
    TargetGroup  = aws_lb_target_group.tg.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu_high" {
  alarm_name          = "${var.project_name}-asg-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}
