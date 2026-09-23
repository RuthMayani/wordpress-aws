output "efs_file_system_id" {
  value = aws_efs_file_system.wordpress.id
}

output "efs_access_point_id" {
  value = aws_efs_access_point.wordpress.id
}

output "security_group_ids" {
  value = {
    for name, group in aws_security_group.tier :
    name => group.id
  }
}
