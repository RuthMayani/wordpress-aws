output "database_address" {
  description = "Private MySQL hostname"
  value       = aws_db_instance.wordpress.address
}

output "database_port" {
  value = aws_db_instance.wordpress.port
}

output "database_name" {
  value = aws_db_instance.wordpress.db_name
}

output "database_master_secret_arn" {
  description = "Secrets Manager reference; not the password"
  value       = aws_db_instance.wordpress.master_user_secret[0].secret_arn
}
