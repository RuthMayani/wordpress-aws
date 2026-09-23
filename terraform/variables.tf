variable "aws_region" {
  description = "AWS region for the project"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "wordpress-ha"
}

variable "vpc_cidr" {
  description = "IPv4 address range for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}
