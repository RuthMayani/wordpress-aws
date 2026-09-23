resource "aws_secretsmanager_secret" "wordpress_application" {
  name_prefix             = "${var.project_name}-application-"
  description             = "Restricted WordPress database credentials"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-application"
  }
}

output "application_secret_arn" {
  description = "Secret reference for the WordPress database account"
  value       = aws_secretsmanager_secret.wordpress_application.arn
}
