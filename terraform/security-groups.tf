resource "aws_security_group" "tier" {
  for_each = toset(["alb", "application", "database", "efs"])

  name_prefix = "${var.project_name}-${each.key}-"
  description = "Security group for ${each.key}"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${each.key}"
  }
}

locals {
  internal_connections = {
    alb_to_app = {
      source      = "alb"
      destination = "application"
      port        = 80
    }
    app_to_db = {
      source      = "application"
      destination = "database"
      port        = 3306
    }
    app_to_efs = {
      source      = "application"
      destination = "efs"
      port        = 2049
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "public_http" {
  security_group_id = aws_security_group.tier["alb"].id
  description       = "Public HTTP access to the load balancer"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "internal" {
  for_each = local.internal_connections

  security_group_id = aws_security_group.tier[each.value.destination].id
  referenced_security_group_id = aws_security_group.tier[
    each.value.source
  ].id

  description = each.key
  ip_protocol = "tcp"
  from_port   = each.value.port
  to_port     = each.value.port
}

resource "aws_vpc_security_group_egress_rule" "internal" {
  for_each = local.internal_connections

  security_group_id = aws_security_group.tier[each.value.source].id
  referenced_security_group_id = aws_security_group.tier[
    each.value.destination
  ].id

  description = each.key
  ip_protocol = "tcp"
  from_port   = each.value.port
  to_port     = each.value.port
}

resource "aws_vpc_security_group_egress_rule" "application_web" {
  for_each = toset(["80", "443"])

  security_group_id = aws_security_group.tier["application"].id
  description       = "Outbound web access for updates and AWS APIs"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.key)
  to_port           = tonumber(each.key)
}
