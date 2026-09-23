resource "aws_efs_file_system" "wordpress" {
  creation_token   = "${var.project_name}-content"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "${var.project_name}-content"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count = 2

  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = aws_subnet.application[count.index].id
  security_groups = [aws_security_group.tier["efs"].id]
}

resource "aws_efs_access_point" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id

  posix_user {
    uid = 33
    gid = 33
  }

  root_directory {
    path = "/wordpress-content"

    creation_info {
      owner_uid   = 33
      owner_gid   = 33
      permissions = "0755"
    }
  }

  tags = {
    Name = "${var.project_name}-content"
  }
}

resource "aws_efs_file_system_policy" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "elasticfilesystem:Client*"
        Resource  = aws_efs_file_system.wordpress.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_efs_backup_policy" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id

  backup_policy {
    status = "ENABLED"
  }
}
