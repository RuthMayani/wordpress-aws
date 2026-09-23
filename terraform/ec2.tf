data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "wordpress" {
  name_prefix   = "${var.project_name}-"
  image_id      = data.aws_ssm_parameter.amazon_linux.value
  instance_type = "t3.small"

  iam_instance_profile {
    name = aws_iam_instance_profile.wordpress.name
  }

  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = [aws_security_group.tier["application"].id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  credit_specification {
    cpu_credits = "standard"
  }

  user_data = base64encode(templatefile(
    "${path.module}/../scripts/bootstrap.sh",
    {
      runtime_installer_b64  = filebase64("${path.module}/../scripts/install-runtime.sh")
      runtime_package_uri    = "s3://${aws_s3_object.runtime.bucket}/${aws_s3_object.runtime.key}"
      runtime_package_sha    = local.runtime_sha256
      aws_region             = var.aws_region
      database_address       = aws_db_instance.wordpress.address
      application_secret_arn = aws_secretsmanager_secret.wordpress_application.arn
      efs_id                 = aws_efs_file_system.wordpress.id
      efs_access_point       = aws_efs_access_point.wordpress.id
    }
  ))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "${var.project_name}-app"
      Project     = var.project_name
      Environment = "lab"
      ManagedBy   = "Terraform"
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
    }
  }
}

resource "aws_autoscaling_group" "wordpress" {
  target_group_arns = [aws_lb_target_group.wordpress.arn]

  name = "${var.project_name}-app"

  min_size         = 2
  desired_capacity = 2
  max_size         = 4

  vpc_zone_identifier = aws_subnet.application[*].id

  health_check_type         = "ELB"
  health_check_grace_period = 600
  wait_for_capacity_timeout = "15m"

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = aws_launch_template.wordpress.latest_version
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  depends_on = [
    aws_s3_object.runtime,
    aws_iam_role_policy.download_runtime,
    aws_efs_mount_target.wordpress,
    aws_efs_file_system_policy.wordpress,
    aws_iam_role_policy.wordpress,
    aws_iam_role_policy_attachment.ssm,
    aws_route.application_internet,
    aws_route_table_association.application,
    aws_vpc_security_group_ingress_rule.internal,
    aws_vpc_security_group_egress_rule.internal,
    aws_vpc_security_group_egress_rule.application_web
  ]
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.wordpress.name
}
