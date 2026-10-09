data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------- Web tier (nginx) ----------
resource "aws_launch_template" "web" {
  name_prefix            = "${var.project}-web-"
  image_id               = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id]
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.web.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile("${path.module}/user_data/web.sh", {
    bucket   = aws_s3_bucket.artifacts.id
    region   = var.region
    web_hash = local.web_hash
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-web" }
  }
}

resource "aws_autoscaling_group" "web" {
  name                      = "${var.project}-web-asg"
  min_size                  = var.asg_min
  max_size                  = var.asg_max
  desired_capacity          = var.asg_min
  vpc_zone_identifier       = aws_subnet.web[*].id
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  depends_on = [
    aws_nat_gateway.nat,
    aws_route_table_association.web,
    aws_s3_object.web,
  ]
}

resource "aws_autoscaling_policy" "web" {
  name                   = "${var.project}-web-req-per-target"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.web.arn_suffix}"
    }
    target_value = var.requests_per_target
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener.https]
}

# ---------- App tier (Flask + gunicorn) ----------
resource "aws_launch_template" "app" {
  name_prefix            = "${var.project}-app-"
  image_id               = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.app.id]
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(templatefile("${path.module}/user_data/app.sh", {
    bucket        = aws_s3_bucket.artifacts.id
    region        = var.region
    app_hash      = local.app_hash
    db_host       = aws_db_instance.main.address
    db_name       = var.db_name
    secret_arn    = aws_db_instance.main.master_user_secret[0].secret_arn
    cookie_secure = tostring(local.enable_https)
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-app" }
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.project}-app-asg"
  min_size                  = var.asg_min
  max_size                  = var.asg_max
  desired_capacity          = var.asg_min
  vpc_zone_identifier       = aws_subnet.app[*].id
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  depends_on = [
    aws_nat_gateway.nat,
    aws_route_table_association.app,
    aws_s3_object.app,
  ]
}

resource "aws_autoscaling_policy" "app" {
  name                   = "${var.project}-app-req-per-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = var.requests_per_target
  }

  depends_on = [aws_lb_listener_rule.api]
}
