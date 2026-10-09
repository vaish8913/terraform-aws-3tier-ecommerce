# Artifact bucket: Terraform uploads the website and API code, instances pull it at boot.
locals {
  mime = {
    html = "text/html; charset=utf-8"
    css  = "text/css; charset=utf-8"
    js   = "application/javascript; charset=utf-8"
  }
  web_files = fileset("${path.module}/web", "**")
  app_files = fileset("${path.module}/app", "**")

  # Hashes go into user_data, so a code change updates the launch template and rolls the instances.
  web_hash = md5(join("", [for f in sort(tolist(local.web_files)) : filemd5("${path.module}/web/${f}")]))
  app_hash = md5(join("", [for f in sort(tolist(local.app_files)) : filemd5("${path.module}/app/${f}")]))
}

resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${var.project}-artifacts-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "web" {
  for_each     = local.web_files
  bucket       = aws_s3_bucket.artifacts.id
  key          = "web/${each.value}"
  source       = "${path.module}/web/${each.value}"
  etag         = filemd5("${path.module}/web/${each.value}")
  content_type = lookup(local.mime, regex("[^.]+$", each.value), "application/octet-stream")
}

resource "aws_s3_object" "app" {
  for_each = local.app_files
  bucket   = aws_s3_bucket.artifacts.id
  key      = "app/${each.value}"
  source   = "${path.module}/app/${each.value}"
  etag     = filemd5("${path.module}/app/${each.value}")
}

# Free S3 gateway endpoint so artifact downloads skip the NAT gateway
resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.main.id
  service_name    = "com.amazonaws.${var.region}.s3"
  route_table_ids = [aws_route_table.private.id]
}
