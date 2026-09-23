output "vpc_id" {
  description = "Project VPC ID"
  value       = aws_vpc.main.id
}

output "availability_zones" {
  description = "Selected Availability Zones"
  value       = local.azs
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "application_subnet_ids" {
  value = aws_subnet.application[*].id
}

output "database_subnet_ids" {
  value = aws_subnet.database[*].id
}
