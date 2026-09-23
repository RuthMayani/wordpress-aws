resource "aws_db_subnet_group" "wordpress" {
  name       = "${var.project_name}-database"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "${var.project_name}-database"
  }
}

resource "aws_db_parameter_group" "wordpress" {
  name_prefix = "${var.project_name}-mysql84-"
  family      = "mysql8.4"
  description = "WordPress MySQL settings"

  parameter {
    name         = "require_secure_transport"
    value        = "ON"
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "wordpress" {
  identifier = "${var.project_name}-mysql"

  engine               = "mysql"
  engine_version       = "8.4.6"
  instance_class       = "db.t4g.micro"
  db_name              = "wordpress"
  username             = "wpadmin"
  port                 = 3306
  parameter_group_name = aws_db_parameter_group.wordpress.name

  manage_master_user_password = true

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az               = true
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids = [aws_security_group.tier["database"].id]

  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-mysql-final"

  enabled_cloudwatch_logs_exports = ["error"]

  tags = {
    Name = "${var.project_name}-mysql"
  }
}
