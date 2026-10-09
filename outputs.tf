output "site_url" {
  value = local.enable_https ? "https://${var.domain_name}" : "http://${aws_lb.main.dns_name}"
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.main.address
}

output "db_secret_arn" {
  value = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.id
}
