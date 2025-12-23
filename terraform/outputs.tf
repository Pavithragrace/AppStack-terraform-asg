output "application_url" {
  value       = "http://${aws_lb.alb.dns_name}"
  description = "Open this and test /health"
}

output "alb_dns_name" { value = aws_lb.alb.dns_name }
output "db_host" { value = aws_db_instance.postgres.address }
output "static_bucket" { value = aws_s3_bucket.static.bucket }
output "waf_arn" { value = aws_wafv2_web_acl.waf.arn }
output "ssm_prefix" { value = "/${var.project_name}" }
