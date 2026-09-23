resource "aws_iam_role" "wordpress" {
  name_prefix = "${var.project_name}-ec2-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "wordpress" {
  name_prefix = "${var.project_name}-ec2-"
  role        = aws_iam_role.wordpress.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.wordpress.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "wordpress" {
  name = "${var.project_name}-application-access"
  role = aws_iam_role.wordpress.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadApplicationCredentials"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.wordpress_application.arn
      },
      {
        Sid    = "MountWordPressContent"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = aws_efs_file_system.wordpress.arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = aws_efs_access_point.wordpress.arn
          }
          Bool = {
            "aws:SecureTransport" = "true"
          }
        }
      }
    ]
  })
}

output "wordpress_instance_profile_name" {
  value = aws_iam_instance_profile.wordpress.name
}
