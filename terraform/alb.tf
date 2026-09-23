resource "aws_lb" "wordpress" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.tier["alb"].id]
  subnets         = aws_subnet.public[*].id

  drop_invalid_header_fields = true
  idle_timeout               = 60

  depends_on = [
    aws_internet_gateway.main,
    aws_route.public_internet,
    aws_route_table_association.public
  ]

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "wordpress" {
  name        = "${var.project_name}-web"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/healthz.php"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-web"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

output "load_balancer_url" {
  description = "Temporary HTTP address for the lab"
  value       = "http://${aws_lb.wordpress.dns_name}"
}

output "wordpress_target_group_arn" {
  value = aws_lb_target_group.wordpress.arn
}
